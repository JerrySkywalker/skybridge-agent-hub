[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "local-safe",
  "-UseTempDatabase",
  "-OutputDir", $outputDir
)

if ([string]$result.schema -ne "skybridge.mvp_demo.local_safe.v1") { throw "Unexpected MVP demo schema." }
if ([string]$result.demo_result -notin @("pass", "partial")) { throw "MVP demo did not pass or partially pass." }
if ([string]$result.demo_result -eq "partial" -and @($result.blockers).Count -lt 1) { throw "Partial MVP demo must include explicit blockers." }
Assert-True $result.task_created "task_created"
Assert-True $result.worker_registered "worker_registered"
Assert-True $result.task_claimed "task_claimed"
Assert-True $result.task_started "task_started"
Assert-True $result.task_completed "task_completed"
Assert-True $result.artifacts_written "artifacts_written"
Assert-True $result.artifact_report_written "artifact_report_written"
Assert-False $result.codex_called "codex_called"
Assert-False $result.pr_created "pr_created"
Assert-False $result.branch_created "branch_created"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.run_forever_started "run_forever_started"
Assert-TokenPrintedFalse $result

foreach ($file in @(
  "mvp-demo-report.json",
  "mvp-demo-report.md",
  "mvp-demo-state.json",
  "mvp-demo-events.json",
  "mvp-demo-task.json",
  "mvp-demo-worker.json",
  "mvp-demo-safety.json",
  "mvp-demo-command-transcript.txt",
  "mvp-demo-artifact-index.json"
)) {
  Assert-FileExists "$outputDir/$file"
}

$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-report.json")
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-report.md")
$transcriptText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-command-transcript.txt")
Assert-NoUnsafeText $reportText
Assert-NoUnsafeText $markdownText
Assert-NoUnsafeText $transcriptText

Complete-Smoke "skybridge-mvp-demo-local-safe"
