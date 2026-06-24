param(
  [ValidateSet("status", "preview", "fixture", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$OutputDir = "",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SchemaId = "skybridge.matlab_doctor.v1"
$ConfirmationPhrase = "I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$DoctorScriptPath = Join-Path $RepoRoot "scripts\matlab\skybridge_matlab_startup_doctor.m"
$TimeoutSeconds = 120

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 24
}

function ConvertTo-FullPath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) {
    return [IO.Path]::GetFullPath($Path)
  }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function ConvertTo-RelativePath {
  param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetFullPath($RepoRoot)
  if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $full.Replace("\", "/")
}

function Test-OutputDirAllowed {
  param([string]$FullPath)
  $candidate = [IO.Path]::GetFullPath($FullPath).TrimEnd("\", "/")
  $allowedRoots = @(
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent\tmp\matlab-doctor")).TrimEnd("\", "/"),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent\tmp\matlab-golden-trial")).TrimEnd("\", "/"),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot "results\skybridge\matlab-golden-trial")).TrimEnd("\", "/")
  )
  foreach ($root in $allowedRoots) {
    if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($candidate.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($candidate.StartsWith($root + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  $false
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  [bool]($Text -match "(?i)\b(command|cmd|shell|powershell|pwsh|bash|system\s*\(|eval\s*\(|dos\s*\(|unix\s*\(|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|authorization|bearer|cookie)\b")
}

function Get-MatlabCommand {
  $cmd = Get-Command matlab -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  $cmd = Get-Command matlab.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  return $null
}

function Get-MatlabExecutableSafePath {
  param($CommandInfo)
  if (-not $CommandInfo) { return "" }
  if ($CommandInfo.Source) { return [string]$CommandInfo.Source }
  if ($CommandInfo.Path) { return [string]$CommandInfo.Path }
  [string]$CommandInfo.Name
}

function Escape-MatlabLiteral {
  param([string]$Value)
  $Value.Replace("'", "''").Replace("\", "/")
}

function Get-DoctorConfig {
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  $outputValue = $OutputDir
  if ([string]::IsNullOrWhiteSpace($outputValue)) {
    $outputValue = ".agent/tmp/matlab-doctor/startup"
  }
  if (Test-UnsafeText $outputValue) { $blockers.Add("unsafe_output_text_detected") | Out-Null }
  $fullOutputDir = ConvertTo-FullPath $outputValue
  if (-not (Test-OutputDirAllowed $fullOutputDir)) { $blockers.Add("output_dir_outside_allowed_paths") | Out-Null }
  if (-not (Test-Path -LiteralPath $DoctorScriptPath -PathType Leaf)) { $blockers.Add("fixed_script_missing") | Out-Null }

  [pscustomobject]@{
    output_dir_full = $fullOutputDir
    output_dir = ConvertTo-RelativePath $fullOutputDir
    doctor_summary_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "doctor_summary.json")
    doctor_metrics_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "doctor_metrics.csv")
    blockers = @($blockers.ToArray() | Select-Object -Unique)
    warnings = @($warnings.ToArray() | Select-Object -Unique)
  }
}

function New-DoctorRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Config,
    [bool]$MatlabDetected,
    [string]$MatlabExecutable = "",
    [string]$MatlabVersionSummary = "",
    [bool]$BatchSupported = $false,
    [bool]$StartupOk = $false,
    [string]$LicenseStatus = "not_checked",
    [bool]$OutputWriteOk = $false,
    [bool]$MinimalComputeOk = $false,
    [string]$FailureCategory = "",
    [string]$FailureSummary = "",
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    [bool]$MatlabInvoked = $false
  )
  [pscustomobject]@{
    schema = $SchemaId
    ok = $Ok
    mode = $Mode
    matlab_detected = $MatlabDetected
    matlab_executable = $MatlabExecutable
    matlab_version_summary = $MatlabVersionSummary
    batch_supported = $BatchSupported
    startup_ok = $StartupOk
    license_ok = ($LicenseStatus -eq "ok")
    license_status = $LicenseStatus
    fixed_script_visible = (Test-Path -LiteralPath $DoctorScriptPath -PathType Leaf)
    output_dir = $Config.output_dir
    doctor_summary_path = $Config.doctor_summary_path
    doctor_metrics_path = $Config.doctor_metrics_path
    output_write_ok = $OutputWriteOk
    minimal_compute_ok = $MinimalComputeOk
    matlab_invoked = $MatlabInvoked
    failure_category = $FailureCategory
    failure_summary = $FailureSummary
    blockers = @($Blockers)
    warnings = @($Warnings)
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  }
}

function Get-FailureCategoryFromText {
  param([string]$Text, [string]$Default)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $Default }
  if ($Text -match "(?i)license|licensing|checkout") { return "matlab_license_unavailable" }
  if ($Text -match "(?i)unrecognized option|unknown option|invalid option|batch") { return "matlab_batch_unsupported" }
  if ($Text -match "(?i)no display|desktop|java") { return "matlab_startup_environment_failed" }
  $Default
}

function Invoke-FixedMatlabDoctorProcess {
  param($Config, [string]$Mode)
  $matlab = Get-MatlabCommand
  if (-not $matlab) {
    return [pscustomobject]@{ ok = $false; exit_code = $null; failure_category = "matlab_not_available"; matlab_invoked = $false; batch_supported = $false }
  }

  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $stdoutPath = [IO.Path]::GetTempFileName()
  $stderrPath = [IO.Path]::GetTempFileName()
  try {
    $matlabDir = Split-Path -Parent $DoctorScriptPath
    $fixedCode = "try, addpath('$(Escape-MatlabLiteral $matlabDir)'); skybridge_matlab_startup_doctor('$(Escape-MatlabLiteral $Config.output_dir_full)'); catch, exit(1); end; exit(0);"
    $argumentList = if ($Mode -eq "batch") {
      @("-batch", $fixedCode)
    } else {
      @("-nosplash", "-nodesktop", "-r", $fixedCode)
    }
    $startParams = @{
      FilePath = Get-MatlabExecutableSafePath $matlab
      ArgumentList = $argumentList
      PassThru = $true
      RedirectStandardOutput = $stdoutPath
      RedirectStandardError = $stderrPath
      WorkingDirectory = $matlabDir
    }
    if ($IsWindows) { $startParams.WindowStyle = "Hidden" }
    $process = Start-Process @startParams
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
      try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
      return [pscustomobject]@{ ok = $false; exit_code = $null; failure_category = "matlab_startup_timeout"; matlab_invoked = $true; batch_supported = ($Mode -eq "batch") }
    }
    $outputText = ""
    try {
      $outputText = ((Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue) + " " + (Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue))
    } catch {
      $outputText = ""
    }
    $summaryPath = Join-Path $Config.output_dir_full "doctor_summary.json"
    $metricsPath = Join-Path $Config.output_dir_full "doctor_metrics.csv"
    $filesOk = (Test-Path -LiteralPath $summaryPath -PathType Leaf) -and (Test-Path -LiteralPath $metricsPath -PathType Leaf)
    $ok = ($process.ExitCode -eq 0 -and $filesOk)
    $category = if ($ok) { "" } else { Get-FailureCategoryFromText -Text $outputText -Default "matlab_startup_or_license_failed" }
    [pscustomobject]@{
      ok = $ok
      exit_code = [int]$process.ExitCode
      failure_category = $category
      matlab_invoked = $true
      batch_supported = ($Mode -eq "batch" -and $ok)
    }
  } finally {
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

function Read-DoctorSummary {
  param($Config)
  $path = Join-Path $Config.output_dir_full "doctor_summary.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { return $null }
}

function Write-FixtureDoctorOutputs {
  param($Config)
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  Set-Content -LiteralPath (Join-Path $Config.output_dir_full "doctor_metrics.csv") -Value @("eta,h_km,P,score", "2,500,3,0.012") -Encoding UTF8
  [pscustomobject]@{
    schema = "skybridge.matlab_doctor_summary.v1"
    matlab_version_summary = "fixture"
    minimal_compute_ok = $true
    metrics_path = $Config.doctor_metrics_path
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Config.output_dir_full "doctor_summary.json") -Encoding UTF8
}

$config = Get-DoctorConfig
$matlabCommand = Get-MatlabCommand
$matlabDetected = [bool]$matlabCommand
$matlabExecutable = Get-MatlabExecutableSafePath $matlabCommand

if ($Command -eq "status") {
  $blockers = @($config.blockers)
  if (-not $matlabDetected) { $blockers += "matlab_not_available" }
  $result = New-DoctorRecord -Mode "status" -Ok ($blockers.Count -eq 0) -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -FailureCategory "" -FailureSummary "status_only_no_matlab_invocation" -Blockers $blockers -Warnings @("apply_requires_exact_confirmation")
} elseif ($Command -eq "safe-summary") {
  $result = New-DoctorRecord -Mode "safe-summary" -Ok $true -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -FailureSummary "fixed_matlab_startup_diagnostic_available_without_raw_output"
} elseif ($Command -eq "preview") {
  $blockers = @($config.blockers)
  if (-not $matlabDetected) { $blockers += "matlab_not_available" }
  $previewFailureCategory = ""
  if ($blockers.Count -gt 0) { $previewFailureCategory = [string]($blockers | Select-Object -First 1) }
  $result = New-DoctorRecord -Mode "preview" -Ok ($blockers.Count -eq 0) -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -FailureCategory $previewFailureCategory -FailureSummary "preview_only_no_matlab_invocation" -Blockers ($blockers | Select-Object -Unique)
} elseif ($Command -eq "fixture") {
  if ($config.blockers.Count -gt 0) {
    $result = New-DoctorRecord -Mode "fixture" -Ok $false -Config $config -MatlabDetected $false -FailureCategory ($config.blockers | Select-Object -First 1) -FailureSummary "fixture_blocked" -Blockers $config.blockers
  } else {
    Write-FixtureDoctorOutputs -Config $config
    $result = New-DoctorRecord -Mode "fixture" -Ok $true -Config $config -MatlabDetected $false -MatlabVersionSummary "fixture" -BatchSupported $false -StartupOk $true -LicenseStatus "fixture_not_checked" -OutputWriteOk $true -MinimalComputeOk $true -Warnings @("fixture_mode_no_matlab_invocation")
  }
} elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -FailureCategory "missing_exact_confirmation" -FailureSummary "Exact confirmation is required before MATLAB startup diagnostic apply." -Blockers @("missing_exact_confirmation")
} elseif ($config.blockers.Count -gt 0) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -FailureCategory ($config.blockers | Select-Object -First 1) -FailureSummary "Doctor apply preconditions failed." -Blockers $config.blockers
} elseif (-not $matlabDetected) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -MatlabDetected $false -FailureCategory "matlab_not_available" -FailureSummary "MATLAB executable was not found; no startup diagnostic invocation occurred." -Blockers @("matlab_not_available")
} else {
  $batch = Invoke-FixedMatlabDoctorProcess -Config $config -Mode "batch"
  $final = $batch
  $warnings = @()
  if (-not $batch.ok) {
    $fallback = Invoke-FixedMatlabDoctorProcess -Config $config -Mode "fallback"
    if ($fallback.ok) {
      $final = $fallback
      $warnings += "batch_mode_failed_fixed_fallback_succeeded"
    }
  }
  $summary = Read-DoctorSummary -Config $config
  $versionSummary = if ($summary -and $summary.matlab_version_summary) { [string]$summary.matlab_version_summary } else { "" }
  $metricsPath = Join-Path $config.output_dir_full "doctor_metrics.csv"
  $summaryPath = Join-Path $config.output_dir_full "doctor_summary.json"
  $outputWriteOk = (Test-Path -LiteralPath $summaryPath -PathType Leaf) -and (Test-Path -LiteralPath $metricsPath -PathType Leaf)
  $minimalOk = $outputWriteOk -and ($summary -and $summary.minimal_compute_ok -eq $true)
  $failureCategory = if ($final.ok) { "" } else { [string]$final.failure_category }
  if ([string]::IsNullOrWhiteSpace($failureCategory) -and -not $final.ok) { $failureCategory = "matlab_startup_or_license_failed" }
  $licenseStatus = "unknown_or_failed"
  $failureSummary = "MATLAB fixed startup diagnostic failed before producing a complete sanitized output set."
  $applyBlockers = @($failureCategory)
  if ($final.ok) {
    $licenseStatus = "ok"
    $failureSummary = "MATLAB fixed startup diagnostic completed."
    $applyBlockers = @()
  }
  $result = New-DoctorRecord -Mode "apply" -Ok ([bool]$final.ok) -Config $config -MatlabDetected $matlabDetected -MatlabExecutable $matlabExecutable -MatlabVersionSummary $versionSummary -BatchSupported ([bool]$batch.ok) -StartupOk ([bool]$final.ok) -LicenseStatus $licenseStatus -OutputWriteOk ([bool]$outputWriteOk) -MinimalComputeOk ([bool]$minimalOk) -FailureCategory $failureCategory -FailureSummary $failureSummary -Blockers $applyBlockers -Warnings $warnings -MatlabInvoked ([bool]$final.matlab_invoked)
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
