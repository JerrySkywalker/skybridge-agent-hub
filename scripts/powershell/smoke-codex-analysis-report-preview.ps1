[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$taskId = "smoke-codex-analysis-preview-" + [Guid]::NewGuid().ToString("n")
$inputDir = ".agent/tmp/matlab-golden-trial/$taskId"
$outputDir = ".agent/tmp/codex-analysis-report/$taskId"
$fullInputDir = Join-Path $RepoRoot $inputDir
$fullOutputDir = Join-Path $RepoRoot $outputDir

function Write-FixtureInputs {
  New-Item -ItemType Directory -Force -Path $fullInputDir | Out-Null
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
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "manifest.json") -Encoding UTF8
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
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $fullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-Runner {
  param([string]$Command)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command $Command `
    -TaskId $taskId `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$inputDir/manifest.json" `
    -InputSummary "$inputDir/summary.json" `
    -InputMetrics "$inputDir/metrics.csv" `
    -OutputDir $outputDir `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Write-FixtureInputs
  $status = Invoke-Runner -Command "status"
  if ([string]$status.schema -ne "skybridge.codex_analysis_report_runner.v1") { throw "Unexpected status schema." }
  Assert-False $status.codex_invoked "status codex_invoked"
  Assert-False $status.matlab_run_called "status matlab_run_called"
  Assert-TokenPrintedFalse $status

  $preview = Invoke-Runner -Command "preview"
  if ($preview.ok -ne $true) { throw "Codex report preview should be ok: $($preview.blockers -join ';')" }
  if ($preview.validation_status -ne "preview_only") { throw "Expected preview_only validation." }
  Assert-False $preview.codex_invoked "preview codex_invoked"
  Assert-False $preview.report_exists "preview report_exists"
  Assert-False $preview.matlab_run_called "preview matlab_run_called"
  Assert-False $preview.worker_loop_started "preview worker_loop_started"
  Assert-TokenPrintedFalse $preview

  if (Test-Path -LiteralPath (Join-Path $fullOutputDir "report.md") -PathType Leaf) {
    throw "Preview should not create report.md."
  }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-preview"
    schema = $preview.schema
    codex_invoked = $false
    report_created = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
