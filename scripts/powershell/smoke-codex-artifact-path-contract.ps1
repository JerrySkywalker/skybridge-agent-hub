[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$taskId = "smoke-codex-artifact-path-contract-338-001"
$inputDir = ".agent/tmp/matlab-golden-trial/smoke-codex-artifact-path-contract"
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

function Invoke-Runner {
  param([string[]]$ScriptArgs)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript @ScriptArgs -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Write-FixtureInputs
  $preview = Invoke-Runner @(
    "-Command", "preview",
    "-TaskId", $taskId,
    "-WorkerId", "jerry-win-local-01",
    "-InputManifest", "$inputDir/manifest.json",
    "-InputSummary", "$inputDir/summary.json",
    "-InputMetrics", "$inputDir/metrics.csv",
    "-OutputDir", $outputDir
  )
  if ($preview.ok -ne $true) { throw "Path contract preview failed: $($preview.blockers -join ';')" }
  $expected = ".agent/tmp/codex-analysis-report/$taskId/report.md"
  if ([string]$preview.output_report_path -ne $expected) { throw "Unexpected report path: $($preview.output_report_path)" }
  if ([string]$preview.output_report_path -match "\.agent/tmp/c($|/)|\.agent/tmp/codex$") { throw "Report path was truncated." }
  if ($preview.report_exists -ne $false) { throw "Preview must not create report." }

  $unsafe = Invoke-Runner @(
    "-Command", "preview",
    "-TaskId", $taskId,
    "-WorkerId", "jerry-win-local-01",
    "-InputManifest", "$inputDir/manifest.json",
    "-InputSummary", "$inputDir/summary.json",
    "-InputMetrics", "$inputDir/metrics.csv",
    "-OutputDir", ".agent/tmp/c"
  )
  if ($unsafe.ok -ne $false) { throw "Truncated output path should be rejected." }
  if ((@($unsafe.blockers) -join ";") -notmatch "output_path_invalid|output_path_suspiciously_truncated") { throw "Unexpected truncated-path blockers: $($unsafe.blockers -join ';')" }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-artifact-path-contract"
    output_report_path = $preview.output_report_path
    truncated_path_rejected = $true
    report_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
