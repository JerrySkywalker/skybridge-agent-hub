[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo"
$reportPath = Join-Path $RepoRoot "$outputDir/mvp-demo-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "local-safe", "-UseTempDatabase", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
Assert-False $report.codex_called "codex_called"
Assert-False $report.hermes_live_called "hermes_live_called"
Assert-False $report.mcp_run_called "mcp_run_called"
Assert-False $report.worker_loop_started "worker_loop_started"
Assert-False $report.queue_runner_started "queue_runner_started"
Assert-False $report.run_forever_started "run_forever_started"
Assert-TokenPrintedFalse $report

$taskArtifact = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-task.json") | ConvertFrom-Json
Assert-False $taskArtifact.task_payload.planner_metadata.codex_called "task planner codex_called"
$transcript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-command-transcript.txt")
Assert-NoUnsafeText $transcript

Complete-Smoke "skybridge-mvp-demo-no-codex"
