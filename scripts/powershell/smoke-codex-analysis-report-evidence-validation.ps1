[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$successTaskId = "smoke-codex-report-success-" + [Guid]::NewGuid().ToString("n")
$failureTaskId = "smoke-codex-report-failure-" + [Guid]::NewGuid().ToString("n")
$shimTaskId = "smoke-codex-report-powershell-shim-" + [Guid]::NewGuid().ToString("n")
$successInputDir = ".agent/tmp/matlab-golden-trial/$successTaskId"
$failureInputDir = ".agent/tmp/matlab-golden-trial/$failureTaskId"
$shimInputDir = ".agent/tmp/matlab-golden-trial/$shimTaskId"
$successOutputDir = ".agent/tmp/codex-analysis-report/$successTaskId"
$failureOutputDir = ".agent/tmp/codex-analysis-report/$failureTaskId"
$shimOutputDir = ".agent/tmp/codex-analysis-report/$shimTaskId"
$successFullInputDir = Join-Path $RepoRoot $successInputDir
$failureFullInputDir = Join-Path $RepoRoot $failureInputDir
$shimFullInputDir = Join-Path $RepoRoot $shimInputDir
$successFullOutputDir = Join-Path $RepoRoot $successOutputDir
$failureFullOutputDir = Join-Path $RepoRoot $failureOutputDir
$shimFullOutputDir = Join-Path $RepoRoot $shimOutputDir
$fakeCodexDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-fake-codex-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
$pwshExe = (Get-Process -Id $PID).Path

function Write-FixtureInputs {
  param([string]$FullInputDir)
  New-Item -ItemType Directory -Force -Path $FullInputDir | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    worker_id = "jerry-win-local-01"
    template_id = "matlab-parameter-sweep.v1"
    runner_id = "matlab-parameter-sweep-runner.v1"
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
    combination_count = 2
    generated_at = "2026-06-24T00:00:00.000Z"
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $FullInputDir "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    worker_id = "jerry-win-local-01"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    min_score = 0.024
    max_score = 0.036
    mean_score = 0.03
    validation_status = "passed"
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $FullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $FullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-Runner {
  param(
    [string]$Command,
    [string]$TaskId,
    [string]$InputDir,
    [string]$OutputDir,
    [switch]$Confirm
  )
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $runnerScript,
    "-Command",
    $Command,
    "-TaskId",
    $TaskId,
    "-WorkerId",
    "smoke-codex-worker",
    "-InputManifest",
    "$InputDir/manifest.json",
    "-InputSummary",
    "$InputDir/summary.json",
    "-InputMetrics",
    "$InputDir/metrics.csv",
    "-OutputDir",
    $OutputDir,
    "-Json"
  )
  if ($Confirm) {
    $args += "-Confirm"
    $args += @("-ConfirmationText", "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY")
  }
  $raw = & $pwshExe @args
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Write-FixtureInputs -FullInputDir $successFullInputDir
  $success = Invoke-Runner -Command "fixture" -TaskId $successTaskId -InputDir $successInputDir -OutputDir $successOutputDir
  if ($success.ok -ne $true) { throw "Fixture success output failed." }
  if ($success.evidence.ok -ne $true) { throw "Success evidence ok should be true." }
  if ($success.evidence.report_exists -ne $true) { throw "Success evidence report_exists mismatch." }
  if (@($success.evidence.changed_files).Count -ne 1) { throw "Success evidence should list exactly one changed file." }
  foreach ($relative in @($success.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Success evidence listed nonexistent file: $relative" }
  }
  Assert-False $success.evidence.raw_codex_log_included "success raw_codex_log_included"
  Assert-False $success.evidence.raw_prompt_included "success raw_prompt_included"
  Assert-False $success.evidence.raw_stdout_included "success raw_stdout_included"
  Assert-False $success.evidence.raw_stderr_included "success raw_stderr_included"
  Assert-False $success.evidence.matlab_run_called "success matlab_run_called"
  Assert-False $success.evidence.worker_loop_started "success worker_loop_started"
  Assert-TokenPrintedFalse $success.evidence

  Write-FixtureInputs -FullInputDir $failureFullInputDir
  $env:PATH = [System.IO.Path]::GetTempPath()
  $failure = Invoke-Runner -Command "apply" -TaskId $failureTaskId -InputDir $failureInputDir -OutputDir $failureOutputDir -Confirm
  if ($failure.ok -ne $false) { throw "Apply without Codex on PATH should fail." }
  if ($failure.evidence.ok -ne $false) { throw "Failure evidence ok should be false." }
  if (@($failure.evidence.changed_files).Count -ne 0) { throw "Failure evidence should not list nonexistent changed_files." }
  if (@($failure.evidence.existing_outputs).Count -ne 0) { throw "Failure evidence should not list nonexistent existing_outputs." }
  if (@($failure.evidence.expected_outputs_missing).Count -ne 1) { throw "Failure evidence should list one missing report." }
  if ($failure.evidence.report_exists -ne $false) { throw "Failure evidence report_exists should be false." }
  Assert-False $failure.evidence.raw_codex_log_included "failure raw_codex_log_included"
  Assert-False $failure.evidence.raw_prompt_included "failure raw_prompt_included"
  Assert-False $failure.evidence.raw_stdout_included "failure raw_stdout_included"
  Assert-False $failure.evidence.raw_stderr_included "failure raw_stderr_included"
  Assert-False $failure.evidence.matlab_run_called "failure matlab_run_called"
  Assert-False $failure.evidence.worker_loop_started "failure worker_loop_started"
  Assert-TokenPrintedFalse $failure.evidence

  Write-FixtureInputs -FullInputDir $shimFullInputDir
  New-Item -ItemType Directory -Force -Path $fakeCodexDir | Out-Null
  @'
$outIndex = [Array]::IndexOf($args, "-o")
if ($outIndex -lt 0 -or $outIndex + 1 -ge $args.Count) { exit 2 }
$outputPath = $args[$outIndex + 1]
$null = [Console]::In.ReadToEnd()
@(
  "# Fake Codex Analysis Report",
  "",
  "This report summarizes a synthetic runner validation, not a scientific conclusion.",
  "",
  "- Completed combinations: 2",
  "- Failed combinations: 0",
  "- token_printed=false"
) -join "`r`n" | Set-Content -LiteralPath $outputPath -Encoding UTF8
exit 0
'@ | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.ps1") -Encoding UTF8
  $env:PATH = $fakeCodexDir
  $shim = Invoke-Runner -Command "apply" -TaskId $shimTaskId -InputDir $shimInputDir -OutputDir $shimOutputDir -Confirm
  if ($shim.ok -ne $true) { throw "Apply with PowerShell Codex shim should succeed." }
  if ($shim.evidence.ok -ne $true) { throw "PowerShell shim evidence ok should be true." }
  if ($shim.evidence.codex_invoked -ne $true) { throw "PowerShell shim should be classified as codex_invoked." }
  if (@($shim.evidence.changed_files).Count -ne 1) { throw "PowerShell shim evidence should list exactly one changed file." }
  if ($shim.evidence.raw_codex_log_included -ne $false) { throw "PowerShell shim raw_codex_log_included should be false." }
  if ($shim.evidence.raw_stdout_included -ne $false) { throw "PowerShell shim raw_stdout_included should be false." }
  if ($shim.evidence.raw_stderr_included -ne $false) { throw "PowerShell shim raw_stderr_included should be false." }
  Assert-TokenPrintedFalse $shim.evidence

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-evidence-validation"
    success_changed_files_count = @($success.evidence.changed_files).Count
    success_report_exists = [bool]$success.evidence.report_exists
    failure_changed_files_count = @($failure.evidence.changed_files).Count
    failure_existing_outputs_count = @($failure.evidence.existing_outputs).Count
    failure_expected_outputs_missing_count = @($failure.evidence.expected_outputs_missing).Count
    powershell_shim_supported = [bool]$shim.evidence.codex_invoked
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  $env:PATH = $oldPath
  Remove-Item -LiteralPath $successFullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $failureFullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $shimFullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $successFullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $failureFullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $shimFullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fakeCodexDir -Recurse -Force -ErrorAction SilentlyContinue
}
