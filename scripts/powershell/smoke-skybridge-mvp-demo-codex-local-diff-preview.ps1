[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-local-diff-preview",
  "-OutputDir", $outputDir
)

if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v4") { throw "Unexpected Codex local diff schema." }
if ([string]$result.validation_status -ne "preview_passed") { throw "Codex local diff preview did not pass." }
Assert-True $result.would_call_codex "would_call_codex"
Assert-True $result.would_create_isolated_workspace "would_create_isolated_workspace"
Assert-True $result.would_generate_diff "would_generate_diff"
Assert-True $result.would_use_git_index_collector "would_use_git_index_collector"
Assert-True $result.would_generate_non_empty_patch "would_generate_non_empty_patch"
Assert-True $result.would_run_codex_doctor "would_run_codex_doctor"
Assert-False $result.cleanup_requested "cleanup_requested"
Assert-False $result.cleanup_completed "cleanup_completed"
if ([string]$result.workspace_setup_method -ne "git_worktree") { throw "workspace_setup_method must be git_worktree." }
Assert-True $result.git_index_collector_used "git_index_collector_used"
Assert-False $result.hash_comparison_used "hash_comparison_used"
Assert-False $result.codex_called "codex_called"
if ([int]$result.codex_call_count -ne 0) { throw "codex_call_count must be 0 in preview." }
Assert-False $result.pr_created "pr_created"
Assert-False $result.branch_pushed "branch_pushed"
Assert-False $result.commit_created "commit_created"
Assert-False $result.tui_created_branch "tui_created_branch"
Assert-False $result.tui_created_pr "tui_created_pr"
Assert-TokenPrintedFalse $result

foreach ($file in @(
  "codex-local-diff-report.json",
  "codex-local-diff-report.md",
  "codex-local-diff-state.json",
  "codex-local-diff-task.json",
  "codex-local-diff-worker.json",
  "codex-local-diff-preflight.json",
  "codex-local-diff-prompt.md",
  "codex-local-diff-stdout.log",
  "codex-local-diff-stderr.log",
  "codex-local-diff-last-message.md",
  "codex-local-diff-changed-files.json",
  "codex-local-diff-allowlist-check.json",
  "codex-local-diff-review-summary.md",
  "codex-local-diff.patch",
  "codex-local-diff-safety.json",
  "codex-local-diff-collector-diagnostics.json",
  "codex-local-diff-execution-diagnostics.json",
  "codex-local-diff-failure-classification.json",
  "codex-local-diff-cleanup-report.json",
  "codex-local-diff-cleanup-report.md",
  "codex-local-diff-worktree-list-before.txt",
  "codex-local-diff-worktree-list-after.txt",
  "codex-local-diff-cleanup-safety.json",
  "codex-local-diff-artifact-index.json"
)) {
  Assert-FileExists "$outputDir/$file"
}

$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json")
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-report.md")
Assert-NoUnsafeText $reportText
Assert-NoUnsafeText $markdownText

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-preview"
