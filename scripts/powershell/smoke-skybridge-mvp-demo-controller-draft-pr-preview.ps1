[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo-pr"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "controller-draft-pr-preview",
  "-OutputDir", $outputDir
)

if ([string]$result.schema -ne "skybridge.mvp_demo.controller_draft_pr.v1") { throw "Unexpected controller draft PR schema." }
if ([string]$result.validation_status -ne "preview_passed") { throw "Controller draft PR preview did not pass." }
Assert-True $result.would_create_branch "would_create_branch"
Assert-True $result.would_create_draft_pr "would_create_draft_pr"
Assert-True $result.branch_policy_passed "branch_policy_passed"
Assert-True $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
Assert-False $result.controller_created_branch "controller_created_branch"
Assert-False $result.controller_created_draft_pr "controller_created_draft_pr"
Assert-False $result.pr_created "pr_created"
Assert-False $result.codex_called "codex_called"
Assert-False $result.tui_created_branch "tui_created_branch"
Assert-False $result.tui_created_pr "tui_created_pr"
Assert-TokenPrintedFalse $result

foreach ($file in @(
  "mvp-pr-demo-report.json",
  "mvp-pr-demo-report.md",
  "mvp-pr-demo-state.json",
  "mvp-pr-demo-task.json",
  "mvp-pr-demo-worker.json",
  "mvp-pr-demo-preflight.json",
  "mvp-pr-demo-branch-plan.json",
  "mvp-pr-demo-allowlist-check.json",
  "mvp-pr-demo-pr-metadata.json",
  "mvp-pr-demo-provider-report.json",
  "mvp-pr-demo-safety.json",
  "mvp-pr-demo-artifact-index.json"
)) {
  Assert-FileExists "$outputDir/$file"
}

$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-report.json")
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-report.md")
Assert-NoUnsafeText $reportText
Assert-NoUnsafeText $markdownText

Complete-Smoke "skybridge-mvp-demo-controller-draft-pr-preview"
