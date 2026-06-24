param(
  [ValidateSet("status", "preview", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$MatlabExecutable = "",
  [ValidateSet("batch", "fixed-fallback")]
  [string]$RunMode = "batch",
  [string]$HomeRoot = "",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SchemaId = "skybridge.matlab_local_config.v1"
$ConfirmationPhrase = "I_UNDERSTAND_CONFIGURE_LOCAL_MATLAB_EXECUTABLE_ONLY"

function Resolve-HomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    return [IO.Path]::GetFullPath($HomeRoot)
  }
  if (-not [string]::IsNullOrWhiteSpace($HOME)) {
    return [IO.Path]::GetFullPath($HOME)
  }
  return [Environment]::GetFolderPath("UserProfile")
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  [bool]($Text -match "(?i)\b(secret|token|authorization|bearer|cookie|license\s*key|activation\s*key|registry|system\s*path|machine\s*path|deploy|dns|cloudflare|openresty|authelia|github settings|server-root)\b")
}

function Read-ConfigValue {
  param([string]$Path, [string]$Name)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return ""
  }
  $text = Get-Content -Raw -LiteralPath $Path
  $pattern = "(?m)^\s*(?:\`$env:)?$([regex]::Escape($Name))\s*=\s*['""]?([^'""]+)"
  $match = [regex]::Match($text, $pattern)
  if (-not $match.Success) { return "" }
  return $match.Groups[1].Value.Trim()
}

function ConvertTo-SafePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  return $Path.Trim().Trim('"').Trim("'")
}

function Get-ConfigPaths {
  $homeRootPath = Resolve-HomeRoot
  $skybridgeDir = Join-Path $homeRootPath ".skybridge"
  [pscustomobject]@{
    home_root = $homeRootPath
    skybridge_dir = $skybridgeDir
    config_path = Join-Path $skybridgeDir "matlab.env.ps1"
  }
}

function New-ConfigRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Paths,
    [string]$Executable,
    [string]$ExecutableSource,
    [string]$RunModeValue,
    [bool]$WouldMutate,
    [bool]$DidMutate,
    [string]$FailureCategory = "",
    [string]$FailureSummary = "",
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @()
  )
  [pscustomobject]@{
    schema = $SchemaId
    ok = $Ok
    mode = $Mode
    config_path = [string]$Paths.config_path
    config_present = (Test-Path -LiteralPath $Paths.config_path -PathType Leaf)
    matlab_executable = $Executable
    matlab_executable_source = $ExecutableSource
    matlab_executable_exists = (-not [string]::IsNullOrWhiteSpace($Executable) -and (Test-Path -LiteralPath $Executable -PathType Leaf))
    run_mode = $RunModeValue
    confirmation_required = ($Mode -eq "preview" -or $Mode -eq "apply")
    confirmation_text = $ConfirmationPhrase
    would_mutate = $WouldMutate
    did_mutate = $DidMutate
    writes_user_config_only = $true
    writes_token = $false
    writes_license_key = $false
    modifies_matlab_installation = $false
    modifies_system_path = $false
    modifies_registry = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_invoked = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    failure_category = $FailureCategory
    failure_summary = $FailureSummary
    blockers = @($Blockers)
    warnings = @($Warnings)
    token_printed = $false
  }
}

function Resolve-CurrentConfig {
  param($Paths)
  $configuredExe = Read-ConfigValue -Path $Paths.config_path -Name "SKYBRIDGE_MATLAB_EXE"
  $configuredMode = Read-ConfigValue -Path $Paths.config_path -Name "SKYBRIDGE_MATLAB_RUN_MODE"
  if ([string]::IsNullOrWhiteSpace($configuredMode)) { $configuredMode = "batch" }
  [pscustomobject]@{
    executable = ConvertTo-SafePath $configuredExe
    run_mode = $configuredMode
  }
}

$paths = Get-ConfigPaths
$current = Resolve-CurrentConfig -Paths $paths
$requestedExe = ConvertTo-SafePath $MatlabExecutable
$effectiveExe = if (-not [string]::IsNullOrWhiteSpace($requestedExe)) { $requestedExe } else { $current.executable }
$source = if (-not [string]::IsNullOrWhiteSpace($requestedExe)) { "parameter" } elseif (-not [string]::IsNullOrWhiteSpace($current.executable)) { "user_config" } else { "missing" }
$blockers = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($effectiveExe)) { $blockers.Add("matlab_executable_not_configured") | Out-Null }
elseif (Test-UnsafeText $effectiveExe) { $blockers.Add("unsafe_matlab_executable_text") | Out-Null }
elseif (-not (Test-Path -LiteralPath $effectiveExe -PathType Leaf)) { $blockers.Add("matlab_executable_not_found") | Out-Null }

if ($Command -eq "status") {
  $failureCategory = ""
  if ($blockers.Count -gt 0) { $failureCategory = [string]($blockers | Select-Object -First 1) }
  $result = New-ConfigRecord -Mode "status" -Ok ($blockers.Count -eq 0) -Paths $paths -Executable $effectiveExe -ExecutableSource $source -RunModeValue $current.run_mode -WouldMutate $false -DidMutate $false -FailureCategory $failureCategory -FailureSummary "status_only_no_config_write" -Blockers ($blockers | Select-Object -Unique)
} elseif ($Command -eq "safe-summary") {
  $result = New-ConfigRecord -Mode "safe-summary" -Ok $true -Paths $paths -Executable $effectiveExe -ExecutableSource $source -RunModeValue $current.run_mode -WouldMutate $false -DidMutate $false -FailureSummary "local_matlab_config_helper_writes_user_level_executable_metadata_only"
} elseif ($Command -eq "preview") {
  $failureCategory = if ($blockers.Count -gt 0) { [string]($blockers | Select-Object -First 1) } else { "" }
  $result = New-ConfigRecord -Mode "preview" -Ok ($blockers.Count -eq 0) -Paths $paths -Executable $effectiveExe -ExecutableSource $source -RunModeValue $RunMode -WouldMutate $true -DidMutate $false -FailureCategory $failureCategory -FailureSummary "preview_only_no_config_write" -Blockers ($blockers | Select-Object -Unique)
} elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
  $result = New-ConfigRecord -Mode "apply" -Ok $false -Paths $paths -Executable $effectiveExe -ExecutableSource $source -RunModeValue $RunMode -WouldMutate $true -DidMutate $false -FailureCategory "missing_exact_confirmation" -FailureSummary "Exact confirmation is required before writing user-level MATLAB config." -Blockers @("missing_exact_confirmation")
} elseif ($blockers.Count -gt 0) {
  $result = New-ConfigRecord -Mode "apply" -Ok $false -Paths $paths -Executable $effectiveExe -ExecutableSource $source -RunModeValue $RunMode -WouldMutate $true -DidMutate $false -FailureCategory ([string]($blockers | Select-Object -First 1)) -FailureSummary "MATLAB config apply preconditions failed." -Blockers ($blockers | Select-Object -Unique)
} else {
  New-Item -ItemType Directory -Force -Path $paths.skybridge_dir | Out-Null
  $lines = @(
    "# SkyBridge local MATLAB runtime config. Safe metadata only; no credential values or license keys.",
    "`$env:SKYBRIDGE_MATLAB_EXE = '$($effectiveExe.Replace("'", "''"))'",
    "`$env:SKYBRIDGE_MATLAB_RUN_MODE = '$RunMode'"
  )
  Set-Content -LiteralPath $paths.config_path -Value $lines -Encoding UTF8
  $result = New-ConfigRecord -Mode "apply" -Ok $true -Paths $paths -Executable $effectiveExe -ExecutableSource "user_config" -RunModeValue $RunMode -WouldMutate $true -DidMutate $true -FailureSummary "User-level MATLAB executable config written without secrets."
}

if ($Json) {
  $result | ConvertTo-Json -Depth 16
} else {
  $result | Format-List
}
