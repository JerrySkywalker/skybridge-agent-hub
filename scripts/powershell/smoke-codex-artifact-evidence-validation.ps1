[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$taskId = "smoke-codex-artifact-evidence-" + [Guid]::NewGuid().ToString("n")
$inputDir = ".agent/tmp/matlab-golden-trial/$taskId"
$outputDir = ".agent/tmp/codex-analysis-report/$taskId"
$fullInputDir = Join-Path $RepoRoot $inputDir
$fullOutputDir = Join-Path $RepoRoot $outputDir
$fakeCodexDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-fake-codex-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH

function Write-FixtureInputs {
  New-Item -ItemType Directory -Force -Path $fullInputDir | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    validation_status = "passed"
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $fullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-RunnerApply {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command apply `
    -TaskId $taskId `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$inputDir/manifest.json" `
    -InputSummary "$inputDir/summary.json" `
    -InputMetrics "$inputDir/metrics.csv" `
    -OutputDir $outputDir `
    -Confirm `
    -ConfirmationText "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Write-FixtureInputs
  $fixtureRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command fixture `
    -TaskId $taskId `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$inputDir/manifest.json" `
    -InputSummary "$inputDir/summary.json" `
    -InputMetrics "$inputDir/metrics.csv" `
    -OutputDir $outputDir `
    -Json
  $fixture = (($fixtureRaw | Out-String).Trim() | ConvertFrom-Json)
  if ($fixture.evidence.validation_status -ne "passed") { throw "Fixture evidence should pass." }
  if ($fixture.evidence.report_size_bytes -le 0) { throw "Fixture report_size_bytes should be positive." }
  if ($fixture.evidence.fallback_report_used -ne $false) { throw "Fixture fallback_report_used should be false." }

  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $fakeCodexDir | Out-Null
  "@echo off`r`nexit /b 9`r`n" | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.cmd") -Encoding ASCII
  $env:PATH = "$fakeCodexDir;$oldPath"
  $failure = Invoke-RunnerApply
  if ($failure.ok -ne $false) { throw "Nonzero Codex should fail." }
  if ($failure.evidence.validation_status -ne "failed") { throw "Failure validation_status should be failed." }
  if ([string]$failure.evidence.codex_failure_category -ne "codex_nonzero_exit") { throw "Expected codex_nonzero_exit." }
  if (@($failure.evidence.changed_files).Count -ne 0) { throw "Failure without report must not list changed files." }
  if ($failure.evidence.fallback_report_used -ne $false) { throw "Nonzero Codex must not use fallback." }
  Assert-False $failure.evidence.raw_codex_log_included "failure raw_codex_log_included"
  Assert-False $failure.evidence.raw_prompt_included "failure raw_prompt_included"
  Assert-False $failure.evidence.raw_stdout_included "failure raw_stdout_included"
  Assert-False $failure.evidence.raw_stderr_included "failure raw_stderr_included"
  Assert-TokenPrintedFalse $failure.evidence

  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  @"
@echo off
set OUT=
:loop
if "%~1"=="" goto done
if "%~1"=="-o" (
  set OUT=%~2
  shift
  shift
  goto loop
)
shift
goto loop
:done
if not "%OUT%"=="" (
  > "%OUT%" echo # Invalid Codex Report
  >> "%OUT%" echo This is a synthetic runner validation for a synthetic MATLAB golden trial, not a scientific conclusion.
  >> "%OUT%" echo Raw stdout included: false
  >> "%OUT%" echo Raw stderr included: false
)
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.cmd") -Encoding ASCII
  $invalidCodex = Invoke-RunnerApply
  if ($invalidCodex.ok -ne $true) { throw "Successful Codex with invalid report should use deterministic fallback." }
  if ($invalidCodex.evidence.validation_status -ne "passed") { throw "Invalid-report fallback validation_status should pass." }
  if ($invalidCodex.evidence.report_exists -ne $true) { throw "Invalid-report fallback report should exist." }
  if ($invalidCodex.evidence.fallback_report_used -ne $true) { throw "Invalid-report fallback_report_used should be true." }
  if ([string]$invalidCodex.evidence.codex_failure_category -ne "report_validation_failed_after_codex") { throw "Expected report_validation_failed_after_codex." }
  if (@($invalidCodex.evidence.changed_files).Count -ne 1) { throw "Invalid-report fallback should list exactly one changed file." }
  $fallbackReportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $invalidCodex.evidence.output_report_path)
  Assert-NoUnsafeText $fallbackReportText
  if ($fallbackReportText -match "(?i)raw stdout|raw stderr") { throw "Fallback report should not keep forbidden process-stream markers." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-artifact-evidence-validation"
    fixture_report_size_bytes = [int64]$fixture.evidence.report_size_bytes
    nonzero_failure_category = [string]$failure.evidence.codex_failure_category
    invalid_report_fallback_category = [string]$invalidCodex.evidence.codex_failure_category
    failure_changed_files_count = @($failure.evidence.changed_files).Count
    invalid_report_changed_files_count = @($invalidCodex.evidence.changed_files).Count
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  $env:PATH = $oldPath
  Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fakeCodexDir -Recurse -Force -ErrorAction SilentlyContinue
}
