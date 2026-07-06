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
Assert-False $report.pr_created "pr_created"
Assert-False $report.branch_created "branch_created"
Assert-False $report.auto_merge_enabled "auto_merge_enabled"
Assert-False $report.release_created "release_created"
Assert-False $report.tag_created "tag_created"
Assert-False $report.asset_uploaded "asset_uploaded"
Assert-TokenPrintedFalse $report

$taskArtifact = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-demo-task.json") | ConvertFrom-Json
Assert-False $taskArtifact.task_payload.planner_metadata.pr_created "task planner pr_created"
Assert-False $taskArtifact.task_payload.planner_metadata.branch_created "task planner branch_created"

Complete-Smoke "skybridge-mvp-demo-no-pr"
