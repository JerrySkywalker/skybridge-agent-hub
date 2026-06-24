param(
  [ValidateSet("status", "preview", "fixture", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$OutputDir = "",
  [string]$MatlabExecutable = "",
  [string]$HomeRoot = "",
  [ValidateSet("none", "success", "fallback-success", "executable-missing", "batch-unsupported", "license-unavailable", "startup-profile-failed", "working-directory-failed", "output-write-failed", "fixed-script-failed", "unknown-startup-failure")]
  [string]$FixtureCase = "none",
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
$VersionHintPattern = "R[0-9]{4}[ab]"

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

function Resolve-HomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    return [IO.Path]::GetFullPath($HomeRoot)
  }
  if (-not [string]::IsNullOrWhiteSpace($HOME)) {
    return [IO.Path]::GetFullPath($HOME)
  }
  return [Environment]::GetFolderPath("UserProfile")
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
  [bool]($Text -match "(?i)\b(command|cmd|shell|powershell|pwsh|bash|system\s*\(|eval\s*\(|dos\s*\(|unix\s*\(|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|authorization|bearer|cookie|license\s*key|activation\s*key)\b")
}

function Get-SafeMatlabPathText {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  return $Path.Trim().Trim('"').Trim("'")
}

function Find-CommonMatlabExecutable {
  $root = "C:\Program Files\MATLAB"
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return "" }
  $candidates = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "^R[0-9]{4}[ab]$" } |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "bin\matlab.exe" } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  if ($candidates.Count -gt 0) { return [string]$candidates[0] }
  return ""
}

function Get-MatlabVersionHint {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $match = [regex]::Match($Path, $VersionHintPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($match.Success) { return "release_hint=$($match.Value)" }
  return ""
}

function Resolve-MatlabExecutable {
  $homeRootPath = Resolve-HomeRoot
  $configPath = Join-Path $homeRootPath ".skybridge\matlab.env.ps1"
  $sources = New-Object System.Collections.Generic.List[object]
  if (-not [string]::IsNullOrWhiteSpace($MatlabExecutable)) {
    $sources.Add([pscustomobject]@{ source = "parameter"; path = (Get-SafeMatlabPathText $MatlabExecutable) }) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_MATLAB_EXE)) {
    $sources.Add([pscustomobject]@{ source = "environment"; path = (Get-SafeMatlabPathText $env:SKYBRIDGE_MATLAB_EXE) }) | Out-Null
  }
  $configured = Read-ConfigValue -Path $configPath -Name "SKYBRIDGE_MATLAB_EXE"
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    $sources.Add([pscustomobject]@{ source = "user_config"; path = (Get-SafeMatlabPathText $configured) }) | Out-Null
  }

  foreach ($candidate in @($sources.ToArray())) {
    if (Test-UnsafeText $candidate.path) {
      return [pscustomobject]@{
        detected = $false
        path = [string]$candidate.path
        source = [string]$candidate.source
        config_path = $configPath
        failure_category = "matlab_executable_not_found"
        blocker = "unsafe_matlab_executable_text"
      }
    }
    if (Test-Path -LiteralPath $candidate.path -PathType Leaf) {
      return [pscustomobject]@{
        detected = $true
        path = [IO.Path]::GetFullPath($candidate.path)
        source = [string]$candidate.source
        config_path = $configPath
        failure_category = ""
        blocker = ""
      }
    }
    return [pscustomobject]@{
      detected = $false
      path = [string]$candidate.path
      source = [string]$candidate.source
      config_path = $configPath
      failure_category = "matlab_executable_not_found"
      blocker = "matlab_executable_not_found"
    }
  }

  $cmd = Get-Command matlab -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { $cmd = Get-Command matlab.exe -ErrorAction SilentlyContinue | Select-Object -First 1 }
  if ($cmd) {
    $path = if ($cmd.Source) { [string]$cmd.Source } elseif ($cmd.Path) { [string]$cmd.Path } else { [string]$cmd.Name }
    return [pscustomobject]@{
      detected = $true
      path = $path
      source = "path"
      config_path = $configPath
      failure_category = ""
      blocker = ""
    }
  }

  $common = Find-CommonMatlabExecutable
  if (-not [string]::IsNullOrWhiteSpace($common)) {
    return [pscustomobject]@{
      detected = $true
      path = [IO.Path]::GetFullPath($common)
      source = "common_install_path"
      config_path = $configPath
      failure_category = ""
      blocker = ""
    }
  }

  [pscustomobject]@{
    detected = $false
    path = ""
    source = "none"
    config_path = $configPath
    failure_category = "matlab_executable_not_found"
    blocker = "matlab_executable_not_found"
  }
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
  if (-not (Test-Path -LiteralPath $DoctorScriptPath -PathType Leaf)) { $blockers.Add("matlab_fixed_script_failed") | Out-Null }

  [pscustomobject]@{
    output_dir_full = $fullOutputDir
    output_dir = ConvertTo-RelativePath $fullOutputDir
    doctor_summary_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "doctor_summary.json")
    doctor_metrics_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "doctor_metrics.csv")
    doctor_wrapper_path = Join-Path $fullOutputDir "skybridge_doctor_wrapper.m"
    blockers = @($blockers.ToArray() | Select-Object -Unique)
    warnings = @($warnings.ToArray() | Select-Object -Unique)
  }
}

function Get-ExistingOutputPaths {
  param($Config)
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($pair in @(
    @{ full = (Join-Path $Config.output_dir_full "doctor_summary.json"); relative = $Config.doctor_summary_path },
    @{ full = (Join-Path $Config.output_dir_full "doctor_metrics.csv"); relative = $Config.doctor_metrics_path }
  )) {
    if (Test-Path -LiteralPath $pair.full -PathType Leaf) {
      $paths.Add([string]$pair.relative) | Out-Null
    }
  }
  @($paths.ToArray())
}

function Get-CleanStringArray {
  param([string[]]$Values)
  @($Values |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    ForEach-Object { [string]$_ } |
    Select-Object -Unique)
}

function Get-Recommendation {
  param([string]$Mode, [bool]$Ok, [string]$FailureCategory, [bool]$FallbackSupported)
  if ($Ok -and $Mode -in @("status", "preview", "safe-summary")) {
    return "run_fixed_doctor_apply_with_exact_confirmation_before_recovery"
  }
  if ($Ok -and $FallbackSupported) { return "doctor_passed_with_fixed_fallback_mg336_may_rerun_recovery" }
  if ($Ok) { return "doctor_passed_mg336_may_rerun_recovery" }
  switch ($FailureCategory) {
    "matlab_executable_not_found" { "run_local_config_preview_then_configure_matlab_executable_with_exact_confirmation" }
    "matlab_batch_unsupported" { "use_fixed_fallback_if_available_or_repair_matlab_cli_batch_support" }
    "matlab_license_unavailable" { "repair_matlab_license_or_sign_in_locally_then_rerun_doctor" }
    "matlab_startup_profile_failed" { "repair_local_matlab_startup_profile_then_rerun_fixed_doctor" }
    "matlab_working_directory_failed" { "verify_repo_and_fixed_script_paths_then_rerun_doctor" }
    "matlab_output_write_failed" { "repair_allowed_output_directory_permissions_then_rerun_doctor" }
    "matlab_fixed_script_failed" { "inspect_fixed_doctor_script_and_allowed_output_files_without_raw_log_exposure" }
    default { "inspect_sanitized_failure_category_then_rerun_fixed_doctor_after_local_matlab_repair" }
  }
}

function New-DoctorRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Config,
    $Resolution,
    [string]$MatlabVersionSummary = "",
    [bool]$BatchSupported = $false,
    [bool]$FallbackSupported = $false,
    [bool]$StartupOk = $false,
    [string]$LicenseStatus = "not_checked",
    [bool]$OutputWriteOk = $false,
    [bool]$MinimalComputeOk = $false,
    [Nullable[int]]$MatlabExitCode = $null,
    [string]$FailureCategory = "",
    [string]$FailureSummary = "",
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    [bool]$MatlabInvoked = $false
  )
  if ([string]::IsNullOrWhiteSpace($MatlabVersionSummary)) {
    $MatlabVersionSummary = Get-MatlabVersionHint -Path ([string]$Resolution.path)
  }
  $cleanBlockers = Get-CleanStringArray -Values $Blockers
  $cleanWarnings = Get-CleanStringArray -Values $Warnings
  [pscustomobject]@{
    schema = $SchemaId
    ok = $Ok
    mode = $Mode
    matlab_detected = [bool]$Resolution.detected
    matlab_executable = [string]$Resolution.path
    matlab_executable_source = [string]$Resolution.source
    matlab_config_path = ConvertTo-RelativePath ([string]$Resolution.config_path)
    matlab_version_summary = $MatlabVersionSummary
    batch_supported = $BatchSupported
    fallback_supported = $FallbackSupported
    run_mode = if ($BatchSupported) { "batch" } elseif ($FallbackSupported) { "fixed-fallback" } else { "not_available" }
    startup_ok = $StartupOk
    license_ok = ($LicenseStatus -eq "available")
    license_status = $LicenseStatus
    fixed_script_visible = (Test-Path -LiteralPath $DoctorScriptPath -PathType Leaf)
    output_dir = $Config.output_dir
    doctor_summary_path = $Config.doctor_summary_path
    doctor_metrics_path = $Config.doctor_metrics_path
    output_write_ok = $OutputWriteOk
    minimal_compute_ok = $MinimalComputeOk
    matlab_invoked = $MatlabInvoked
    matlab_exit_code = $MatlabExitCode
    existing_outputs = @(Get-ExistingOutputPaths -Config $Config)
    failure_category = $FailureCategory
    failure_summary = $FailureSummary
    recommended_next_action = Get-Recommendation -Mode $Mode -Ok $Ok -FailureCategory $FailureCategory -FallbackSupported $FallbackSupported
    blockers = @($cleanBlockers)
    warnings = @($cleanWarnings)
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
  if ($Text -match "(?i)license|licensing|checkout|activation") { return "matlab_license_unavailable" }
  if ($Text -match "(?i)unrecognized option|unknown option|invalid option|batch") { return "matlab_batch_unsupported" }
  if ($Text -match "(?i)startup\.m|pathdef|prefdir|profile|initialization|java|desktop") { return "matlab_startup_profile_failed" }
  if ($Text -match "(?i)working directory|cannot cd|current folder|no such file or directory") { return "matlab_working_directory_failed" }
  if ($Text -match "(?i)skybridge:|undefined function.*skybridge_matlab_startup_doctor|doctor_summary|doctor_metrics|jsonencode") { return "matlab_fixed_script_failed" }
  return $Default
}

function Test-OutputWrite {
  param($Config)
  try {
    New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
    $probePath = Join-Path $Config.output_dir_full "doctor_write_probe.txt"
    Set-Content -LiteralPath $probePath -Value "ok" -Encoding ASCII
    Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ ok = $true; failure_category = "" }
  } catch {
    return [pscustomobject]@{ ok = $false; failure_category = "matlab_output_write_failed" }
  }
}

function Clear-DoctorOutputSet {
  param($Config)
  foreach ($name in @("doctor_summary.json", "doctor_metrics.csv", "skybridge_doctor_wrapper.m")) {
    Remove-Item -LiteralPath (Join-Path $Config.output_dir_full $name) -Force -ErrorAction SilentlyContinue
  }
}

function Escape-MatlabLiteral {
  param([string]$Value)
  $Value.Replace("'", "''").Replace("\", "/")
}

function Write-DoctorWrapper {
  param($Config)
  $matlabDir = Split-Path -Parent $DoctorScriptPath
  $lines = @(
    "try",
    "  addpath('$(Escape-MatlabLiteral $matlabDir)');",
    "  skybridge_matlab_startup_doctor('$(Escape-MatlabLiteral $Config.output_dir_full)');",
    "catch",
    "  exit(1);",
    "end",
    "exit(0);"
  )
  Set-Content -LiteralPath $Config.doctor_wrapper_path -Value $lines -Encoding ASCII
}

function Invoke-FixedMatlabDoctorProcess {
  param($Config, $Resolution, [ValidateSet("batch", "fallback")] [string]$Mode)
  Clear-DoctorOutputSet -Config $Config
  Write-DoctorWrapper -Config $Config
  $stdoutPath = [IO.Path]::GetTempFileName()
  $stderrPath = [IO.Path]::GetTempFileName()
  try {
    $matlabDir = Split-Path -Parent $DoctorScriptPath
    if (-not (Test-Path -LiteralPath $matlabDir -PathType Container)) {
      return [pscustomobject]@{ ok = $false; exit_code = $null; failure_category = "matlab_working_directory_failed"; matlab_invoked = $false; mode = $Mode }
    }
    $wrapper = Escape-MatlabLiteral $Config.doctor_wrapper_path
    $argumentList = if ($Mode -eq "batch") {
      @("-batch", "run('$wrapper')")
    } else {
      @("-nosplash", "-nodesktop", "-r", "try, run('$wrapper'); catch, exit(1); end; exit(0);")
    }
    $startParams = @{
      FilePath = [string]$Resolution.path
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
      return [pscustomobject]@{ ok = $false; exit_code = $null; failure_category = "unknown_matlab_startup_failure"; matlab_invoked = $true; mode = $Mode }
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
    $category = if ($ok) { "" } else { Get-FailureCategoryFromText -Text $outputText -Default "unknown_matlab_startup_failure" }
    [pscustomobject]@{
      ok = $ok
      exit_code = [int]$process.ExitCode
      failure_category = $category
      matlab_invoked = $true
      mode = $Mode
    }
  } catch {
    $category = Get-FailureCategoryFromText -Text $_.Exception.Message -Default "unknown_matlab_startup_failure"
    [pscustomobject]@{ ok = $false; exit_code = $null; failure_category = $category; matlab_invoked = $false; mode = $Mode }
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
  param($Config, [string]$VersionSummary = "fixture")
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  Set-Content -LiteralPath (Join-Path $Config.output_dir_full "doctor_metrics.csv") -Value @("eta,h_km,P,score", "2,500,3,0.012") -Encoding UTF8
  [pscustomobject]@{
    schema = "skybridge.matlab_doctor_summary.v1"
    matlab_version_summary = $VersionSummary
    minimal_compute_ok = $true
    metrics_path = $Config.doctor_metrics_path
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Config.output_dir_full "doctor_summary.json") -Encoding UTF8
}

function New-FixtureRecord {
  param($Config, $Resolution)
  $case = $FixtureCase
  if ($case -eq "none") { $case = "success" }
  if ($case -eq "success") {
    Write-FixtureDoctorOutputs -Config $Config -VersionSummary "fixture-success"
    return New-DoctorRecord -Mode "fixture" -Ok $true -Config $Config -Resolution $Resolution -MatlabVersionSummary "fixture-success" -BatchSupported $true -FallbackSupported $false -StartupOk $true -LicenseStatus "available" -OutputWriteOk $true -MinimalComputeOk $true -Warnings @("fixture_mode_no_matlab_invocation")
  }
  if ($case -eq "fallback-success") {
    Write-FixtureDoctorOutputs -Config $Config -VersionSummary "fixture-fallback"
    return New-DoctorRecord -Mode "fixture" -Ok $true -Config $Config -Resolution $Resolution -MatlabVersionSummary "fixture-fallback" -BatchSupported $false -FallbackSupported $true -StartupOk $true -LicenseStatus "available" -OutputWriteOk $true -MinimalComputeOk $true -Warnings @("fixture_mode_no_matlab_invocation", "batch_mode_failed_fixed_fallback_succeeded")
  }
  $category = switch ($case) {
    "executable-missing" { "matlab_executable_not_found" }
    "batch-unsupported" { "matlab_batch_unsupported" }
    "license-unavailable" { "matlab_license_unavailable" }
    "startup-profile-failed" { "matlab_startup_profile_failed" }
    "working-directory-failed" { "matlab_working_directory_failed" }
    "output-write-failed" { "matlab_output_write_failed" }
    "fixed-script-failed" { "matlab_fixed_script_failed" }
    default { "unknown_matlab_startup_failure" }
  }
  $fixtureResolution = $Resolution
  if ($category -eq "matlab_executable_not_found") {
    $fixtureResolution = [pscustomobject]@{
      detected = $false
      path = ""
      source = "fixture"
      config_path = [string]$Resolution.config_path
      failure_category = $category
      blocker = $category
    }
  }
  $licenseStatus = "unknown_or_failed"
  if ($category -eq "matlab_license_unavailable") { $licenseStatus = "unavailable" }
  return New-DoctorRecord -Mode "fixture" -Ok $false -Config $Config -Resolution $fixtureResolution -BatchSupported $false -FallbackSupported $false -StartupOk $false -LicenseStatus $licenseStatus -OutputWriteOk ($category -ne "matlab_output_write_failed") -MinimalComputeOk $false -FailureCategory $category -FailureSummary "Fixture classified $category without invoking MATLAB." -Blockers @($category) -Warnings @("fixture_mode_no_matlab_invocation")
}

$config = Get-DoctorConfig
$resolution = Resolve-MatlabExecutable

if ($Command -eq "status") {
  $blockers = @($config.blockers)
  if (-not [bool]$resolution.detected) { $blockers += [string]$resolution.blocker }
  $failureCategory = if ($blockers.Count -gt 0) { [string]($blockers | Select-Object -First 1) } else { "" }
  $result = New-DoctorRecord -Mode "status" -Ok ($blockers.Count -eq 0) -Config $config -Resolution $resolution -FailureCategory $failureCategory -FailureSummary "status_only_no_matlab_invocation" -Blockers ($blockers | Select-Object -Unique) -Warnings @("apply_requires_exact_confirmation")
} elseif ($Command -eq "safe-summary") {
  $result = New-DoctorRecord -Mode "safe-summary" -Ok $true -Config $config -Resolution $resolution -FailureSummary "fixed_matlab_startup_diagnostic_available_without_raw_output"
} elseif ($Command -eq "preview") {
  $blockers = @($config.blockers)
  if (-not [bool]$resolution.detected) { $blockers += [string]$resolution.blocker }
  $previewFailureCategory = if ($blockers.Count -gt 0) { [string]($blockers | Select-Object -First 1) } else { "" }
  $result = New-DoctorRecord -Mode "preview" -Ok ($blockers.Count -eq 0) -Config $config -Resolution $resolution -FailureCategory $previewFailureCategory -FailureSummary "preview_only_no_matlab_invocation" -Blockers ($blockers | Select-Object -Unique)
} elseif ($Command -eq "fixture") {
  if ($config.blockers.Count -gt 0) {
    $result = New-DoctorRecord -Mode "fixture" -Ok $false -Config $config -Resolution $resolution -FailureCategory ($config.blockers | Select-Object -First 1) -FailureSummary "fixture_blocked" -Blockers $config.blockers
  } else {
    $result = New-FixtureRecord -Config $config -Resolution $resolution
  }
} elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -Resolution $resolution -FailureCategory "missing_exact_confirmation" -FailureSummary "Exact confirmation is required before MATLAB startup diagnostic apply." -Blockers @("missing_exact_confirmation")
} elseif ($config.blockers.Count -gt 0) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -Resolution $resolution -FailureCategory ($config.blockers | Select-Object -First 1) -FailureSummary "Doctor apply preconditions failed." -Blockers $config.blockers
} elseif (-not [bool]$resolution.detected) {
  $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -Resolution $resolution -FailureCategory "matlab_executable_not_found" -FailureSummary "MATLAB executable was not found; no startup diagnostic invocation occurred." -Blockers @("matlab_executable_not_found")
} else {
  $writeProbe = Test-OutputWrite -Config $config
  if (-not $writeProbe.ok) {
    $result = New-DoctorRecord -Mode "apply" -Ok $false -Config $config -Resolution $resolution -FailureCategory "matlab_output_write_failed" -FailureSummary "Allowed MATLAB doctor output directory could not be written." -Blockers @("matlab_output_write_failed")
  } else {
    $batch = Invoke-FixedMatlabDoctorProcess -Config $config -Resolution $resolution -Mode "batch"
    $final = $batch
    $warnings = @()
    $fallback = $null
    if (-not $batch.ok) {
      $fallback = Invoke-FixedMatlabDoctorProcess -Config $config -Resolution $resolution -Mode "fallback"
      if ($fallback.ok) {
        $final = $fallback
        $warnings += "batch_mode_failed_fixed_fallback_succeeded"
      } else {
        $final = $fallback
      }
    }
    $summary = Read-DoctorSummary -Config $config
    $versionSummary = if ($summary -and $summary.matlab_version_summary) { [string]$summary.matlab_version_summary } else { Get-MatlabVersionHint -Path ([string]$resolution.path) }
    $metricsPath = Join-Path $config.output_dir_full "doctor_metrics.csv"
    $summaryPath = Join-Path $config.output_dir_full "doctor_summary.json"
    $outputWriteOk = (Test-Path -LiteralPath $summaryPath -PathType Leaf) -and (Test-Path -LiteralPath $metricsPath -PathType Leaf)
    $minimalOk = $outputWriteOk -and ($summary -and $summary.minimal_compute_ok -eq $true)
    $failureCategory = if ($final.ok) { "" } else { [string]$final.failure_category }
    if ([string]::IsNullOrWhiteSpace($failureCategory) -and -not $final.ok) { $failureCategory = "unknown_matlab_startup_failure" }
    if (-not $final.ok -and $batch.failure_category -eq "matlab_batch_unsupported" -and $null -eq $fallback) {
      $failureCategory = "matlab_batch_unsupported"
    }
    $licenseStatus = if ($final.ok) { "available" } elseif ($failureCategory -eq "matlab_license_unavailable") { "unavailable" } else { "unknown_or_failed" }
    $failureSummary = if ($final.ok) { "MATLAB fixed startup diagnostic completed." } else { "MATLAB fixed startup diagnostic failed before producing a complete sanitized output set." }
    $applyBlockers = if ($final.ok) { @() } else { @($failureCategory) }
    $exitCode = $null
    if ($null -ne $final.exit_code) { $exitCode = [int]$final.exit_code }
    $result = New-DoctorRecord -Mode "apply" -Ok ([bool]$final.ok) -Config $config -Resolution $resolution -MatlabVersionSummary $versionSummary -BatchSupported ([bool]$batch.ok) -FallbackSupported (($null -ne $fallback) -and [bool]$fallback.ok) -StartupOk ([bool]$final.ok) -LicenseStatus $licenseStatus -OutputWriteOk ([bool]$outputWriteOk) -MinimalComputeOk ([bool]$minimalOk) -MatlabExitCode $exitCode -FailureCategory $failureCategory -FailureSummary $failureSummary -Blockers $applyBlockers -Warnings $warnings -MatlabInvoked ([bool]($batch.matlab_invoked -or ($fallback -and $fallback.matlab_invoked)))
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
