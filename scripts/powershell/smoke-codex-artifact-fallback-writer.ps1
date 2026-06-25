[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$taskId = "smoke-codex-artifact-fallback-" + [Guid]::NewGuid().ToString("n")
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
    worker_id = "jerry-win-local-01"
    template_id = "matlab-parameter-sweep.v1"
    runner_id = "matlab-parameter-sweep-runner.v1"
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

try {
  Write-FixtureInputs
  New-Item -ItemType Directory -Force -Path $fakeCodexDir | Out-Null
  "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.cmd") -Encoding ASCII
  $env:PATH = "$fakeCodexDir;$oldPath"
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
  $result = $text | ConvertFrom-Json
  if ($result.ok -ne $true) { throw "Fallback writer apply failed: $($result.blockers -join ';')" }
  if ($result.evidence.validation_status -ne "passed") { throw "Fallback evidence should pass." }
  if ($result.evidence.report_exists -ne $true) { throw "Fallback report should exist." }
  if ([int64]$result.evidence.report_size_bytes -le 0) { throw "Fallback report should be non-empty." }
  if ($result.evidence.fallback_report_used -ne $true) { throw "fallback_report_used should be true." }
  if ([string]$result.evidence.codex_failure_category -ne "report_missing_after_codex") { throw "Expected report_missing_after_codex category." }
  foreach ($relative in @($result.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Nonexistent changed file listed: $relative" }
  }
  $reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.evidence.output_report_path)
  Assert-NoUnsafeText $reportText
  if ($reportText -notmatch "synthetic runner validation" -or $reportText -notmatch "synthetic MATLAB golden trial") { throw "Fallback report missing synthetic validation statement." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-artifact-fallback-writer"
    report_exists = $true
    report_size_bytes = [int64]$result.evidence.report_size_bytes
    fallback_report_used = $true
    changed_files_count = @($result.evidence.changed_files).Count
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
