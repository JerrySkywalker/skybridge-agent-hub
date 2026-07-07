[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$reportPath = Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-local-diff-preview", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$task = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-task.json") | ConvertFrom-Json
$safety = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-safety.json") | ConvertFrom-Json

Assert-False $report.codex_called "codex_called"
if ([int]$report.codex_call_count -ne 0) { throw "codex_call_count must be 0 in preview." }
Assert-False $safety.safety_flags.codex_called "safety codex_called"
if ([int]$safety.safety_flags.codex_call_count -ne 0) { throw "safety codex_call_count must be 0 in preview." }
Assert-True $task.task_payload.planner_metadata.codex_called "task planner codex_called policy"
if (Test-Path -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-codex.jsonl")) {
  throw "Preview must not create a Codex execution log."
}
Assert-False $report.worker_loop_started "worker_loop_started"
Assert-False $report.queue_runner_started "queue_runner_started"
Assert-False $report.run_forever_started "run_forever_started"
Assert-False $report.hermes_live_called "hermes_live_called"
Assert-False $report.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-no-codex-preview"
