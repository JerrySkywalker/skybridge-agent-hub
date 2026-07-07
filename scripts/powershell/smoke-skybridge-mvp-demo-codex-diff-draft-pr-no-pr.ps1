[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-draft-pr"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-diff-draft-pr-preview",
  "-OutputDir", $outputDir
)
$provider = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-provider-report.json") | ConvertFrom-Json

Assert-False $result.pr_created "result.pr_created"
Assert-False $result.branch_pushed "result.branch_pushed"
Assert-False $result.commit_created "result.commit_created"
Assert-False $result.controller_created_branch "result.controller_created_branch"
Assert-False $result.controller_created_draft_pr "result.controller_created_draft_pr"
Assert-False $provider.git_push_called "provider.git_push_called"
Assert-False $provider.gh_pr_create_called "provider.gh_pr_create_called"
Assert-False $provider.github_api_called "provider.github_api_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "skybridge-mvp-demo-codex-diff-draft-pr-no-pr"
