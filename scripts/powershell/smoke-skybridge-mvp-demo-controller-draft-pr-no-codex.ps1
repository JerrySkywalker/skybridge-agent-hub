[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo-pr"
$reportPath = Join-Path $RepoRoot "$outputDir/mvp-pr-demo-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "controller-draft-pr-preview", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$task = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-task.json") | ConvertFrom-Json
$safety = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-safety.json") | ConvertFrom-Json

Assert-False $report.codex_called "codex_called"
Assert-False $report.tui_created_branch "tui_created_branch"
Assert-False $report.tui_created_pr "tui_created_pr"
Assert-False $report.worker_loop_started "worker_loop_started"
Assert-False $report.queue_runner_started "queue_runner_started"
Assert-False $report.run_forever_started "run_forever_started"
Assert-False $report.hermes_live_called "hermes_live_called"
Assert-False $report.mcp_run_called "mcp_run_called"
Assert-False $report.raw_input_persisted "raw_input_persisted"
Assert-False $task.task_payload.planner_metadata.codex_called "task planner codex_called"
Assert-False $task.task_payload.planner_metadata.tui_created_branch "task planner tui_created_branch"
Assert-False $task.task_payload.planner_metadata.tui_created_pr "task planner tui_created_pr"
Assert-False $safety.safety_flags.codex_called "safety codex_called"
Assert-False $safety.safety_flags.tui_created_branch "safety tui_created_branch"
Assert-False $safety.safety_flags.tui_created_pr "safety tui_created_pr"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-controller-draft-pr-no-codex"
