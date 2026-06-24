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
$MatlabDoctorScriptPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"
$MaxCombinationCount = 16
$MatlabTimeoutSeconds = 180
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

function Read-MatlabConfigValue {
  param([string]$Path, [string]$Name)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  $text = Get-Content -Raw -LiteralPath $Path
  $pattern = "(?m)^\s*(?:\`$env:)?$([regex]::Escape($Name))\s*=\s*['""]?([^'""]+)"
  $match = [regex]::Match($text, $pattern)
  if ($match.Success) { return $match.Groups[1].Value.Trim() }
  ""
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
  ""
}

function New-MatlabCommandInfo {
  param([string]$Path, [string]$Source)
  [pscustomobject]@{
    Source = $Path
    Path = $Path
    Name = Split-Path -Leaf $Path
    ResolutionSource = $Source
  }
}

function Get-MatlabCommand {
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  $configPath = Join-Path $profileHome ".skybridge\matlab.env.ps1"
  $configured = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_MATLAB_EXE)) { $env:SKYBRIDGE_MATLAB_EXE } else { Read-MatlabConfigValue -Path $configPath -Name "SKYBRIDGE_MATLAB_EXE" }
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    $candidate = $configured.Trim().Trim('"').Trim("'")
    if (-not (Test-UnsafeCommandText $candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return New-MatlabCommandInfo -Path ([IO.Path]::GetFullPath($candidate)) -Source "user_config"
    }
  }
  $cmd = Get-Command matlab -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  $cmd = Get-Command matlab.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd }
  $common = Find-CommonMatlabExecutable
  if (-not [string]::IsNullOrWhiteSpace($common)) {
    return New-MatlabCommandInfo -Path ([IO.Path]::GetFullPath($common)) -Source "common_install_path"
  }
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
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
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

function Get-ExistingOutputPaths {
  param($Config)
  $existing = New-Object System.Collections.Generic.List[string]
  $pairs = @(
    @{ full = (Join-Path $Config.output_dir_full "manifest.json"); relative = $Config.manifest_path },
    @{ full = (Join-Path $Config.output_dir_full "summary.json"); relative = $Config.summary_path },
    @{ full = (Join-Path $Config.output_dir_full "metrics.csv"); relative = $Config.metrics_path }
  )
  foreach ($pair in $pairs) {
    if (Test-Path -LiteralPath $pair.full -PathType Leaf) {
      $existing.Add([string]$pair.relative) | Out-Null
    }
  }
  @($existing.ToArray())
}

function Get-MissingOutputPaths {
  param($Config)
  $missing = New-Object System.Collections.Generic.List[string]
  $pairs = @(
    @{ full = (Join-Path $Config.output_dir_full "manifest.json"); relative = $Config.manifest_path },
    @{ full = (Join-Path $Config.output_dir_full "summary.json"); relative = $Config.summary_path },
    @{ full = (Join-Path $Config.output_dir_full "metrics.csv"); relative = $Config.metrics_path }
  )
  foreach ($pair in $pairs) {
    if (-not (Test-Path -LiteralPath $pair.full -PathType Leaf)) {
      $missing.Add([string]$pair.relative) | Out-Null
    }
  }
  @($missing.ToArray())
}

function New-SweepEvidence {
  param(
    $Config,
    [string]$ValidationStatus,
    [bool]$MatlabInvoked,
    [Nullable[int]]$MatlabExitCode,
    [int]$CompletedCount,
    [int]$FailedCount,
    [string]$ResultSummary = "",
    [string]$FailureCategory = ""
  )
  $changedFiles = @(Get-ExistingOutputPaths -Config $Config)
  $missingOutputs = @(Get-MissingOutputPaths -Config $Config)
  if ([string]::IsNullOrWhiteSpace($ResultSummary)) {
    $ResultSummary = if ($ValidationStatus -eq "passed") {
      "Synthetic MATLAB parameter sweep produced sanitized manifest, summary, and metrics."
    } else {
      "Synthetic MATLAB parameter sweep failed before producing the complete sanitized output set."
    }
  }
  if ([string]::IsNullOrWhiteSpace($FailureCategory) -and $ValidationStatus -ne "passed") {
    $FailureCategory = $ValidationStatus
  }
  [pscustomobject]@{
    schema = "skybridge.matlab_sweep_evidence.v1"
    ok = ($ValidationStatus -eq "passed")
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    parameter_grid_summary = $Config.parameter_grid_summary
    combination_count = [int]$Config.combination_count
    expected_combination_count = [int]$Config.combination_count
    completed_count = $CompletedCount
    failed_count = $FailedCount
    output_dir = $Config.output_dir
    manifest_path = $Config.manifest_path
    manifest_exists = $changedFiles -contains $Config.manifest_path
    summary_path = $Config.summary_path
    summary_exists = $changedFiles -contains $Config.summary_path
    metrics_path = $Config.metrics_path
    metrics_exists = $changedFiles -contains $Config.metrics_path
    validation_status = $ValidationStatus
    matlab_invoked = $MatlabInvoked
    matlab_exit_code = $MatlabExitCode
    started_at = $null
    completed_at = if ($ValidationStatus -eq "passed") { (Get-Date).ToUniversalTime().ToString("o") } else { $null }
    failed_at = if ($ValidationStatus -eq "passed") { $null } else { (Get-Date).ToUniversalTime().ToString("o") }
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    changed_files = @($changedFiles)
    existing_outputs = @($changedFiles)
    expected_outputs_missing = @($missingOutputs)
    failure_category = $FailureCategory
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
      $manifest = Get-Content -Raw -LiteralPath (Join-Path $Config.output_dir_full "manifest.json") | ConvertFrom-Json
      if ([string]$manifest.schema -ne "skybridge.matlab_sweep_manifest.v1") { $errors.Add("manifest_schema_mismatch") | Out-Null }
      if ([string]$manifest.task_id -ne $TaskId) { $errors.Add("manifest_task_id_mismatch") | Out-Null }
      if ([int]$manifest.combination_count -ne [int]$Config.combination_count) { $errors.Add("manifest_combination_count_mismatch") | Out-Null }
      if ($manifest.raw_stdout_included -ne $false) { $errors.Add("manifest_raw_stdout_flag_not_false") | Out-Null }
      if ($manifest.raw_stderr_included -ne $false) { $errors.Add("manifest_raw_stderr_flag_not_false") | Out-Null }

      $summary = Get-Content -Raw -LiteralPath (Join-Path $Config.output_dir_full "summary.json") | ConvertFrom-Json
      if ([string]$summary.schema -ne "skybridge.matlab_sweep_summary.v1") { $errors.Add("summary_schema_mismatch") | Out-Null }
      if ([string]$summary.task_id -ne $TaskId) { $errors.Add("summary_task_id_mismatch") | Out-Null }
      if ([int]$summary.combination_count -ne [int]$Config.combination_count) { $errors.Add("summary_combination_count_mismatch") | Out-Null }
      if ([int]$summary.completed_count -ne [int]$Config.combination_count) { $errors.Add("summary_completed_count_mismatch") | Out-Null }
      if ([int]$summary.failed_count -ne 0) { $errors.Add("summary_failed_count_mismatch") | Out-Null }
      if ($summary.raw_stdout_included -ne $false) { $errors.Add("raw_stdout_flag_not_false") | Out-Null }
      if ($summary.raw_stderr_included -ne $false) { $errors.Add("raw_stderr_flag_not_false") | Out-Null }
    } catch {
      $errors.Add("summary_parse_failed") | Out-Null
    }
    try {
      $metricsLines = @(Get-Content -LiteralPath (Join-Path $Config.output_dir_full "metrics.csv") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      if ($metricsLines.Count -ne ([int]$Config.combination_count + 1)) { $errors.Add("metrics_combination_count_mismatch") | Out-Null }
      if ($metricsLines[0] -ne "eta,h_km,P,score") { $errors.Add("metrics_header_mismatch") | Out-Null }
    } catch {
      $errors.Add("metrics_parse_failed") | Out-Null
    }
  }
  @($errors.ToArray())
}

function Escape-MatlabLiteral {
  param([string]$Value)
  $Value.Replace("'", "''").Replace("\", "/")
}

function Invoke-MatlabDoctorPreflight {
  param($Config)
  if (-not (Test-Path -LiteralPath $MatlabDoctorScriptPath -PathType Leaf)) {
    return [pscustomobject]@{
      ok = $false
      skipped = $false
      failure_category = "matlab_doctor_script_missing"
      failure_summary = "MATLAB doctor script was not found."
      matlab_invoked = $false
      token_printed = $false
    }
  }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $MatlabDoctorScriptPath `
    -Command apply `
    -OutputDir $Config.output_dir `
    -Confirm `
    -ConfirmationText "I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY" `
    -Json
  $text = ($raw | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) {
    return [pscustomobject]@{
      ok = $false
      skipped = $false
      failure_category = "matlab_doctor_empty_response"
      failure_summary = "MATLAB doctor returned no safe summary."
      matlab_invoked = $false
      token_printed = $false
    }
  }
  $text | ConvertFrom-Json
}

function Invoke-FixedMatlabProcess {
  param(
    $Config,
    [string]$InputPath,
    [ValidateSet("batch", "fallback")]
    [string]$Mode,
    [string]$StdoutPath,
    [string]$StderrPath
  )
  $matlab = Get-MatlabCommand
  if (-not $matlab) {
    return [pscustomobject]@{ exit_code = $null; timed_out = $false; mode = $Mode; failure_category = "matlab_not_available" }
  }
  $matlabDir = Split-Path -Parent $MatlabScriptPath
  $fixedCode = "try, cd('$(Escape-MatlabLiteral $matlabDir)'); addpath('$(Escape-MatlabLiteral $matlabDir)'); skybridge_run_parameter_sweep('$(Escape-MatlabLiteral $InputPath)', '$(Escape-MatlabLiteral $Config.output_dir_full)'); catch, exit(1); end; exit(0);"
  $argumentList = if ($Mode -eq "batch") {
    @("-batch", $fixedCode)
  } else {
    @("-nosplash", "-nodesktop", "-r", $fixedCode)
  }
  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = if ($matlab.Source) { $matlab.Source } else { $matlab.Path }
  foreach ($argument in $argumentList) {
    [void]$processInfo.ArgumentList.Add($argument)
  }
  $processInfo.WorkingDirectory = $matlabDir
  $processInfo.UseShellExecute = $false
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  $processInfo.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $completed = $process.WaitForExit($MatlabTimeoutSeconds * 1000)
  if (-not $completed) {
    try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ exit_code = $null; timed_out = $true; mode = $Mode; failure_category = "matlab_runner_timeout" }
  }
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  Set-Content -LiteralPath $StdoutPath -Value $stdout -Encoding UTF8
  Set-Content -LiteralPath $StderrPath -Value $stderr -Encoding UTF8
  [pscustomobject]@{ exit_code = [int]$process.ExitCode; timed_out = $false; mode = $Mode; failure_category = "" }
}

function Get-RunnerFailureCategory {
  param([string[]]$Errors, $ProcessResult, [bool]$BatchAttempted, [bool]$FallbackAttempted)
  if ($ProcessResult -and $ProcessResult.timed_out) { return "matlab_runner_timeout" }
  if (@($Errors).Count -gt 0) { return "matlab_outputs_missing_or_invalid" }
  if ($ProcessResult -and $null -ne $ProcessResult.exit_code -and [int]$ProcessResult.exit_code -ne 0) {
    if ($BatchAttempted -and -not $FallbackAttempted) { return "matlab_batch_failed" }
    return "matlab_runner_exit_nonzero"
  }
  "matlab_runner_failed"
}

function Invoke-MatlabFixedRunner {
  param($Config)
  $matlab = Get-MatlabCommand
  if (-not $matlab) {
    return [pscustomobject]@{
      ok = $false
      exit_code = $null
      reason = "matlab_not_available"
      evidence = New-SweepEvidence -Config $Config -ValidationStatus "matlab_not_available" -MatlabInvoked:$false -MatlabExitCode $null -CompletedCount 0 -FailedCount ([int]$Config.combination_count) -ResultSummary "MATLAB was not available; no fixed runner invocation occurred." -FailureCategory "matlab_not_available"
    }
  }

  $doctor = Invoke-MatlabDoctorPreflight -Config $Config
  if ($doctor.ok -ne $true) {
    $category = if (-not [string]::IsNullOrWhiteSpace([string]$doctor.failure_category)) { [string]$doctor.failure_category } else { "matlab_doctor_failed" }
    return [pscustomobject]@{
      ok = $false
      exit_code = $null
      reason = $category
      evidence = New-SweepEvidence -Config $Config -ValidationStatus "failed" -MatlabInvoked:([bool]$doctor.matlab_invoked) -MatlabExitCode $null -CompletedCount 0 -FailedCount ([int]$Config.combination_count) -ResultSummary "MATLAB doctor preflight failed; fixed parameter sweep was not invoked." -FailureCategory $category
      doctor = $doctor
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
    $batchAttempt = Invoke-FixedMatlabProcess -Config $Config -InputPath $inputPath -Mode "batch" -StdoutPath $stdoutPath -StderrPath $stderrPath
    $errors = Test-OutputFiles -Config $Config
    $process = $batchAttempt
    $fallbackAttempted = $false
    $batchExitCode = 1
    if ($null -ne $batchAttempt.exit_code) { $batchExitCode = [int]$batchAttempt.exit_code }
    if ($batchExitCode -ne 0 -or @($errors).Count -ne 0) {
      $fallbackAttempted = $true
      $fallbackAttempt = Invoke-FixedMatlabProcess -Config $Config -InputPath $inputPath -Mode "fallback" -StdoutPath $stdoutPath -StderrPath $stderrPath
      $fallbackErrors = Test-OutputFiles -Config $Config
      $fallbackExitCode = 1
      if ($null -ne $fallbackAttempt.exit_code) { $fallbackExitCode = [int]$fallbackAttempt.exit_code }
      if ($fallbackExitCode -eq 0 -and @($fallbackErrors).Count -eq 0) {
        $process = $fallbackAttempt
        $errors = @()
      } else {
        $process = $fallbackAttempt
        $errors = $fallbackErrors
      }
    }
    $passed = ($null -ne $process.exit_code -and [int]$process.exit_code -eq 0 -and @($errors).Count -eq 0)
    $validationStatus = "failed"
    $completedCount = 0
    $failedCount = [int]$Config.combination_count
    if ($passed) {
      $validationStatus = "passed"
      $completedCount = [int]$Config.combination_count
      $failedCount = 0
    }
    $failureCategory = if ($passed) { "" } else { Get-RunnerFailureCategory -Errors $errors -ProcessResult $process -BatchAttempted $true -FallbackAttempted $fallbackAttempted }
    $matlabExitCodeValue = $null
    if ($null -ne $process.exit_code) { $matlabExitCodeValue = [int]$process.exit_code }
    [pscustomobject]@{
      ok = $passed
      exit_code = $matlabExitCodeValue
      reason = if ($passed) { "passed" } else { (@($errors) + $failureCategory) -join ";" }
      evidence = New-SweepEvidence -Config $Config -ValidationStatus $validationStatus -MatlabInvoked:$true -MatlabExitCode $matlabExitCodeValue -CompletedCount $completedCount -FailedCount $failedCount -FailureCategory $failureCategory
      doctor = $doctor
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
