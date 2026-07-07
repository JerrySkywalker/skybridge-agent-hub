[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-draft-pr"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-diff-draft-pr-preview",
  "-OutputDir", $outputDir
)

if ([string]$result.schema -ne "skybridge.mvp_demo.codex_generated_draft_pr.v1") { throw "Unexpected Codex draft PR schema." }
if ([string]$result.validation_status -ne "preview_passed") { throw "Codex draft PR preview did not pass." }
Assert-True $result.would_validate_source_codex_diff "would_validate_source_codex_diff"
Assert-True $result.would_create_branch "would_create_branch"
Assert-True $result.would_create_commit "would_create_commit"
Assert-True $result.would_push_branch "would_push_branch"
Assert-True $result.would_create_draft_pr "would_create_draft_pr"
Assert-True $result.branch_policy_passed "branch_policy_passed"
Assert-True $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
Assert-False $result.controller_created_branch "controller_created_branch"
Assert-False $result.controller_created_commit "controller_created_commit"
Assert-False $result.controller_created_draft_pr "controller_created_draft_pr"
Assert-False $result.pr_created "pr_created"
Assert-False $result.branch_pushed "branch_pushed"
Assert-False $result.commit_created "commit_created"
Assert-False $result.codex_called_in_mg372e2 "codex_called_in_mg372e2"
Assert-False $result.tui_created_branch "tui_created_branch"
Assert-False $result.tui_created_pr "tui_created_pr"
Assert-TokenPrintedFalse $result

foreach ($file in @(
  "codex-draft-pr-report.json",
  "codex-draft-pr-report.md",
  "codex-draft-pr-state.json",
  "codex-draft-pr-task.json",
  "codex-draft-pr-worker.json",
  "codex-draft-pr-preflight.json",
  "codex-draft-pr-source-diff-validation.json",
  "codex-draft-pr-branch-plan.json",
  "codex-draft-pr-allowlist-check.json",
  "codex-draft-pr-pr-metadata.json",
  "codex-draft-pr-provider-report.json",
  "codex-draft-pr-safety.json",
  "codex-draft-pr-artifact-index.json"
)) {
  Assert-FileExists "$outputDir/$file"
}

$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-report.json")
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-report.md")
Assert-NoUnsafeText $reportText
Assert-NoUnsafeText $markdownText

Complete-Smoke "skybridge-mvp-demo-codex-diff-draft-pr-preview"
