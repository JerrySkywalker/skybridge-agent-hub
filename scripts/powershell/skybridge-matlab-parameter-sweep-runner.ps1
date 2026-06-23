param(
  [ValidateSet("status", "preview", "apply", "fixture", "validate-output", "safe-summary")]
  [string]$Command = "preview",
  [string]$TaskId = "live-matlab-golden-task-333-001",
  [string]$WorkerId = "jerry-win-local-01",
  [string]$InputJsonFile = "",
  [string]$OutputDir = "",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$TemplateId = "matlab-parameter-sweep.v1"
$RunnerId = "matlab-parameter-sweep-runner.v1"
$ConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$MatlabScriptPath = Join-Path $RepoRoot "scripts\matlab\skybridge_run_parameter_sweep.m"
$MaxCombinationCount = 16
$DefaultEta = @(2, 3)
$DefaultHKm = @(500)
$DefaultP = @(6)

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 24
}

function ConvertTo-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  return @($Value)
}

function Get-PropertyValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function ConvertTo-NumberArray {
  param($Value, [string]$Name)
  $items = @(ConvertTo-Array $Value)
  if ($items.Count -eq 0) { throw "missing_$Name" }
  $numbers = New-Object System.Collections.Generic.List[double]
  foreach ($item in $items) {
    $text = [string]$item
    $parsed = 0.0
    if (-not [double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
      throw "invalid_$Name"
    }
    $numbers.Add($parsed) | Out-Null
  }
  @($numbers.ToArray())
}

function Test-UnsafeCommandText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return [bool]($Text -match "(?i)\b(command|cmd|shell|powershell|pwsh|bash|system\s*\(|eval\s*\(|dos\s*\(|unix\s*\(|!matlab|!cmd|!powershell|!pwsh|!bash|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|authorization|bearer|cookie)\b")
}

function Get-MatlabCommand {
  $cmd = Get-Command matlab -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  $cmd = Get-Command matlab.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  return $null
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

function Get-RunnerConfig {
  $blockers = New-Object System.Collections.Generic.List[string]
  $rawInput = ""
  $input = $null
  if (-not [string]::IsNullOrWhiteSpace($InputJsonFile)) {
    if (-not (Test-Path -LiteralPath $InputJsonFile -PathType Leaf)) {
      $blockers.Add("input_json_file_missing") | Out-Null
    } else {
      $rawInput = Get-Content -Raw -LiteralPath $InputJsonFile
      if (Test-UnsafeCommandText $rawInput) { $blockers.Add("arbitrary_command_text_detected") | Out-Null }
      try { $input = $rawInput | ConvertFrom-Json } catch { $blockers.Add("input_json_parse_failed") | Out-Null }
    }
  }

  $eta = @($DefaultEta)
  $hKm = @($DefaultHKm)
  $pValues = @($DefaultP)
  if ($input) {
    try {
      if ($null -ne (Get-PropertyValue $input "eta")) { $eta = @(ConvertTo-NumberArray (Get-PropertyValue $input "eta") "eta") }
      if ($null -ne (Get-PropertyValue $input "h_km")) { $hKm = @(ConvertTo-NumberArray (Get-PropertyValue $input "h_km") "h_km") }
      if ($null -ne (Get-PropertyValue $input "P")) { $pValues = @(ConvertTo-NumberArray (Get-PropertyValue $input "P") "P") }
    } catch {
      $blockers.Add([string]$_.Exception.Message) | Out-Null
    }
  }

  $outputValue = $OutputDir
  if ([string]::IsNullOrWhiteSpace($outputValue) -and $input) {
    $outputValue = [string](Get-PropertyValue $input "output_dir")
  }
  if ([string]::IsNullOrWhiteSpace($outputValue)) {
    $outputValue = ".agent/tmp/matlab-golden-trial/$TaskId"
  }
  if (Test-UnsafeCommandText $outputValue) { $blockers.Add("unsafe_output_text_detected") | Out-Null }
  $fullOutputDir = ConvertTo-FullPath $outputValue
  if (-not (Test-OutputDirAllowed $fullOutputDir)) { $blockers.Add("output_dir_outside_allowed_paths") | Out-Null }

  $combinationCount = @($eta).Count * @($hKm).Count * @($pValues).Count
  if ($combinationCount -lt 1) { $blockers.Add("empty_parameter_grid") | Out-Null }
  if ($combinationCount -gt $MaxCombinationCount) { $blockers.Add("parameter_grid_too_large") | Out-Null }
  if (-not (Test-Path -LiteralPath $MatlabScriptPath -PathType Leaf)) { $blockers.Add("matlab_fixture_script_missing") | Out-Null }

  [pscustomobject]@{
    eta = @($eta)
    h_km = @($hKm)
    P = @($pValues)
    combination_count = $combinationCount
    output_dir_full = $fullOutputDir
    output_dir = ConvertTo-RelativePath $fullOutputDir
    manifest_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "manifest.json")
    summary_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "summary.json")
    metrics_path = ConvertTo-RelativePath (Join-Path $fullOutputDir "metrics.csv")
    parameter_grid_summary = "eta=[$(@($eta) -join ',')]; h_km=[$(@($hKm) -join ',')]; P=[$(@($pValues) -join ',')]; combinations=$combinationCount"
    blockers = @($blockers.ToArray() | Select-Object -Unique)
  }
}

function New-RunnerRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Config,
    [string]$ValidationStatus = "not_run",
    [bool]$MatlabInvoked = $false,
    [Nullable[int]]$MatlabExitCode = $null,
    [int]$CompletedCount = 0,
    [int]$FailedCount = 0,
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    [bool]$WouldInvokeMatlab = $false
  )
  [pscustomobject]@{
    schema = "skybridge.matlab_parameter_sweep_runner.v1"
    ok = $Ok
    mode = $Mode
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    parameter_grid_summary = $Config.parameter_grid_summary
    combination_count = [int]$Config.combination_count
    completed_count = $CompletedCount
    failed_count = $FailedCount
    output_dir = $Config.output_dir
    manifest_path = $Config.manifest_path
    summary_path = $Config.summary_path
    metrics_path = $Config.metrics_path
    validation_status = $ValidationStatus
    matlab_available = [bool](Get-MatlabCommand)
    would_invoke_matlab = $WouldInvokeMatlab
    matlab_invoked = $MatlabInvoked
    matlab_exit_code = $MatlabExitCode
    blockers = @($Blockers)
    warnings = @($Warnings)
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  }
}

function Write-JsonFile {
  param([string]$Path, $Value)
  $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-FixtureOutputs {
  param($Config, [bool]$MatlabInvoked = $false, [Nullable[int]]$MatlabExitCode = $null)
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  $scores = New-Object System.Collections.Generic.List[double]
  $csvLines = New-Object System.Collections.Generic.List[string]
  $csvLines.Add("eta,h_km,P,score") | Out-Null
  foreach ($eta in @($Config.eta)) {
    foreach ($h in @($Config.h_km)) {
      foreach ($p in @($Config.P)) {
        $score = [Math]::Round(([double]$eta * [double]$p / [double]$h), 12)
        $scores.Add($score) | Out-Null
        $csvLines.Add(("{0},{1},{2},{3}" -f $eta, $h, $p, $score.ToString("0.############", [Globalization.CultureInfo]::InvariantCulture))) | Out-Null
      }
    }
  }
  Set-Content -LiteralPath (Join-Path $Config.output_dir_full "metrics.csv") -Value $csvLines.ToArray() -Encoding UTF8
  $manifest = [pscustomobject]@{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    parameter_grid_summary = $Config.parameter_grid_summary
    combination_count = [int]$Config.combination_count
    output_dir = $Config.output_dir
    manifest_path = $Config.manifest_path
    summary_path = $Config.summary_path
    metrics_path = $Config.metrics_path
    generated_at = $generatedAt
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  }
  $summary = [pscustomobject]@{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = $TaskId
    worker_id = $WorkerId
    combination_count = [int]$Config.combination_count
    completed_count = [int]$Config.combination_count
    failed_count = 0
    min_score = if ($scores.Count -gt 0) { ($scores | Measure-Object -Minimum).Minimum } else { $null }
    max_score = if ($scores.Count -gt 0) { ($scores | Measure-Object -Maximum).Maximum } else { $null }
    mean_score = if ($scores.Count -gt 0) { [Math]::Round(($scores | Measure-Object -Average).Average, 12) } else { $null }
    validation_status = "passed"
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  }
  Write-JsonFile -Path (Join-Path $Config.output_dir_full "manifest.json") -Value $manifest
  Write-JsonFile -Path (Join-Path $Config.output_dir_full "summary.json") -Value $summary
  New-SweepEvidence -Config $Config -ValidationStatus "passed" -MatlabInvoked:$MatlabInvoked -MatlabExitCode $MatlabExitCode -CompletedCount ([int]$Config.combination_count) -FailedCount 0
}

function New-SweepEvidence {
  param(
    $Config,
    [string]$ValidationStatus,
    [bool]$MatlabInvoked,
    [Nullable[int]]$MatlabExitCode,
    [int]$CompletedCount,
    [int]$FailedCount,
    [string]$ResultSummary = "MG333 synthetic MATLAB parameter sweep produced sanitized manifest, summary, and metrics."
  )
  [pscustomobject]@{
    schema = "skybridge.matlab_sweep_evidence.v1"
    ok = ($ValidationStatus -eq "passed")
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    parameter_grid_summary = $Config.parameter_grid_summary
    combination_count = [int]$Config.combination_count
    completed_count = $CompletedCount
    failed_count = $FailedCount
    output_dir = $Config.output_dir
    manifest_path = $Config.manifest_path
    summary_path = $Config.summary_path
    metrics_path = $Config.metrics_path
    validation_status = $ValidationStatus
    matlab_invoked = $MatlabInvoked
    matlab_exit_code = $MatlabExitCode
    started_at = $null
    completed_at = if ($ValidationStatus -eq "passed") { (Get-Date).ToUniversalTime().ToString("o") } else { $null }
    failed_at = if ($ValidationStatus -eq "passed") { $null } else { (Get-Date).ToUniversalTime().ToString("o") }
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    changed_files = @($Config.manifest_path, $Config.summary_path, $Config.metrics_path)
    result_summary = $ResultSummary
    pr_created = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    token_printed = $false
  }
}

function Test-OutputFiles {
  param($Config)
  $errors = New-Object System.Collections.Generic.List[string]
  foreach ($name in @("manifest.json", "summary.json", "metrics.csv")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Config.output_dir_full $name) -PathType Leaf)) {
      $errors.Add("missing_$name") | Out-Null
    }
  }
  if ($errors.Count -eq 0) {
    try {
      $summary = Get-Content -Raw -LiteralPath (Join-Path $Config.output_dir_full "summary.json") | ConvertFrom-Json
      if ([int]$summary.combination_count -ne [int]$Config.combination_count) { $errors.Add("summary_combination_count_mismatch") | Out-Null }
      if ([int]$summary.completed_count -ne [int]$Config.combination_count) { $errors.Add("summary_completed_count_mismatch") | Out-Null }
      if ($summary.raw_stdout_included -ne $false) { $errors.Add("raw_stdout_flag_not_false") | Out-Null }
      if ($summary.raw_stderr_included -ne $false) { $errors.Add("raw_stderr_flag_not_false") | Out-Null }
    } catch {
      $errors.Add("summary_parse_failed") | Out-Null
    }
  }
  @($errors.ToArray())
}

function Escape-MatlabLiteral {
  param([string]$Value)
  $Value.Replace("'", "''").Replace("\", "/")
}

function Invoke-MatlabFixedRunner {
  param($Config)
  $matlab = Get-MatlabCommand
  if (-not $matlab) {
    return [pscustomobject]@{
      ok = $false
      exit_code = $null
      reason = "matlab_not_available"
      evidence = New-SweepEvidence -Config $Config -ValidationStatus "matlab_not_available" -MatlabInvoked:$false -MatlabExitCode $null -CompletedCount 0 -FailedCount ([int]$Config.combination_count) -ResultSummary "MATLAB was not available; no fixed runner invocation occurred."
    }
  }

  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $inputPath = Join-Path $Config.output_dir_full "runner-input.json"
  $runnerInput = [pscustomobject]@{
    task_id = $TaskId
    worker_id = $WorkerId
    eta = @($Config.eta)
    h_km = @($Config.h_km)
    P = @($Config.P)
  }
  Write-JsonFile -Path $inputPath -Value $runnerInput
  $stdoutPath = [IO.Path]::GetTempFileName()
  $stderrPath = [IO.Path]::GetTempFileName()
  try {
    $matlabDir = Split-Path -Parent $MatlabScriptPath
    $batch = "try, addpath('$(Escape-MatlabLiteral $matlabDir)'); skybridge_run_parameter_sweep('$(Escape-MatlabLiteral $inputPath)', '$(Escape-MatlabLiteral $Config.output_dir_full)'); catch ex, disp(getReport(ex,'basic')); exit(1); end; exit(0);"
    $startParams = @{
      FilePath = if ($matlab.Source) { $matlab.Source } else { $matlab.Path }
      ArgumentList = @("-batch", $batch)
      Wait = $true
      PassThru = $true
      RedirectStandardOutput = $stdoutPath
      RedirectStandardError = $stderrPath
    }
    if ($IsWindows) { $startParams.WindowStyle = "Hidden" }
    $process = Start-Process @startParams
    $errors = Test-OutputFiles -Config $Config
    $passed = ($process.ExitCode -eq 0 -and @($errors).Count -eq 0)
    $validationStatus = "failed"
    $completedCount = 0
    $failedCount = [int]$Config.combination_count
    if ($passed) {
      $validationStatus = "passed"
      $completedCount = [int]$Config.combination_count
      $failedCount = 0
    }
    [pscustomobject]@{
      ok = $passed
      exit_code = [int]$process.ExitCode
      reason = if ($passed) { "passed" } else { (@($errors) + "matlab_exit_$($process.ExitCode)") -join ";" }
      evidence = New-SweepEvidence -Config $Config -ValidationStatus $validationStatus -MatlabInvoked:$true -MatlabExitCode ([int]$process.ExitCode) -CompletedCount $completedCount -FailedCount $failedCount
    }
  } finally {
    Remove-Item -LiteralPath $inputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

$config = Get-RunnerConfig
$matlabAvailable = [bool](Get-MatlabCommand)

if ($Command -eq "status") {
  $result = New-RunnerRecord -Mode "status" -Ok $true -Config $config -ValidationStatus "status_only" -Warnings @("apply_requires_exact_confirmation")
} elseif ($Command -eq "safe-summary") {
  $result = New-RunnerRecord -Mode "safe-summary" -Ok $true -Config $config -ValidationStatus "safe_summary_only" -Warnings @("fixed_runner_only_no_raw_stdout_or_stderr")
} elseif ($Command -eq "preview") {
  $blockers = @($config.blockers)
  $previewStatus = if ($blockers.Count -eq 0) { "preview_only" } else { "blocked" }
  $result = New-RunnerRecord -Mode "preview" -Ok ($blockers.Count -eq 0) -Config $config -ValidationStatus $previewStatus -Blockers $blockers -WouldInvokeMatlab ($blockers.Count -eq 0)
} elseif ($Command -eq "fixture") {
  if ($config.blockers.Count -gt 0) {
    $result = New-RunnerRecord -Mode "fixture" -Ok $false -Config $config -ValidationStatus "blocked" -Blockers $config.blockers
  } else {
    $evidence = Write-FixtureOutputs -Config $config -MatlabInvoked:$false -MatlabExitCode 0
    $result = New-RunnerRecord -Mode "fixture" -Ok $true -Config $config -ValidationStatus "passed" -CompletedCount ([int]$config.combination_count) -FailedCount 0 -Warnings @("fixture_mode_no_matlab_invocation")
    $result | Add-Member -NotePropertyName evidence -NotePropertyValue $evidence
  }
} elseif ($Command -eq "validate-output") {
  $errors = Test-OutputFiles -Config $config
  $validateStatus = if ($errors.Count -eq 0) { "passed" } else { "failed" }
  $validateCompleted = if ($errors.Count -eq 0) { [int]$config.combination_count } else { 0 }
  $validateFailed = if ($errors.Count -eq 0) { 0 } else { [int]$config.combination_count }
  $result = New-RunnerRecord -Mode "validate-output" -Ok ($errors.Count -eq 0) -Config $config -ValidationStatus $validateStatus -CompletedCount $validateCompleted -FailedCount $validateFailed -Blockers $errors
} else {
  if ($config.blockers.Count -gt 0) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "blocked" -Blockers $config.blockers
  } elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "missing_exact_confirmation" -Blockers @("missing_exact_confirmation")
  } elseif (-not $matlabAvailable) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "matlab_not_available" -Blockers @("matlab_not_available")
  } else {
    $apply = Invoke-MatlabFixedRunner -Config $config
    $applyStatus = if ($apply.ok) { "passed" } else { "failed" }
    $applyCompleted = if ($apply.ok) { [int]$config.combination_count } else { 0 }
    $applyFailed = if ($apply.ok) { 0 } else { [int]$config.combination_count }
    $applyBlockers = if ($apply.ok) { @() } else { @($apply.reason) }
    $result = New-RunnerRecord -Mode "apply" -Ok ([bool]$apply.ok) -Config $config -ValidationStatus $applyStatus -MatlabInvoked:$true -MatlabExitCode $apply.exit_code -CompletedCount $applyCompleted -FailedCount $applyFailed -Blockers $applyBlockers
    $result | Add-Member -NotePropertyName evidence -NotePropertyValue $apply.evidence
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
