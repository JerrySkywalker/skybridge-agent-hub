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
$provider = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-provider-report.json") | ConvertFrom-Json

Assert-False $report.controller_created_branch "controller_created_branch"
Assert-False $report.controller_created_draft_pr "controller_created_draft_pr"
Assert-False $report.pr_created "pr_created"
Assert-False $report.demo_pr_left_open "demo_pr_left_open"
Assert-False $report.demo_pr_marked_ready "demo_pr_marked_ready"
Assert-False $report.demo_pr_merged "demo_pr_merged"
Assert-False $report.auto_merge_enabled "auto_merge_enabled"
Assert-False $report.release_created "release_created"
Assert-False $report.tag_created "tag_created"
Assert-False $report.asset_uploaded "asset_uploaded"
Assert-False $provider.git_push_called "provider.git_push_called"
Assert-False $provider.gh_pr_create_called "provider.gh_pr_create_called"
Assert-False $provider.github_api_called "provider.github_api_called"
if ([int]$provider.provider_call_count -ne 0) { throw "Preview provider_call_count must be 0." }
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-controller-draft-pr-no-pr"
