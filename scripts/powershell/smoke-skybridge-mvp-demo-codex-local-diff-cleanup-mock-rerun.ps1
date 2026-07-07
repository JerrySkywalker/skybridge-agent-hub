[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff/cleanup-mock-rerun-smoke"
$resolvedOutputDir = Join-Path $RepoRoot $outputDir
$worktreePath = Join-Path $resolvedOutputDir "worktree"
$tmpRoot = Join-Path $RepoRoot ".agent/tmp/skybridge-mvp-codex-diff"
if (-not ([System.IO.Path]::GetFullPath($resolvedOutputDir).StartsWith([System.IO.Path]::GetFullPath($tmpRoot)))) {
  throw "Refusing to prepare cleanup mock rerun outside .agent/tmp/skybridge-mvp-codex-diff."
}
if (Test-Path -LiteralPath $worktreePath) {
  git worktree remove --force $worktreePath 2>$null
}
if (Test-Path -LiteralPath $resolvedOutputDir) {
  Remove-Item -LiteralPath $resolvedOutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

try {
  git worktree add --detach $worktreePath HEAD | Out-Null
  $result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
    "-Mode", "codex-local-diff-mock-success",
    "-OutputDir", $outputDir,
    "-CleanExistingCodexWorktree",
    "-ConfirmationText", "I_UNDERSTAND_AUTHORIZE_MG372D2R_CLEAN_STALE_CODEX_DIFF_WORKTREE_AND_RERUN_CODEX_ONCE",
    "-CodexTimeoutSeconds", "30"
  )

  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v4") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "pass") { throw "Cleanup mock rerun did not pass." }
  Assert-True $result.fixture_mode "fixture_mode"
  Assert-True $result.cleanup_requested "cleanup_requested"
  Assert-True $result.cleanup_completed "cleanup_completed"
  Assert-True $result.stale_worktree_detected "stale_worktree_detected"
  Assert-True $result.stale_worktree_cleaned "stale_worktree_cleaned"
  Assert-True $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 1) { throw "codex_call_count must be 1." }
  if (@($result.changed_files).Count -ne 1 -or [string]$result.changed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
    throw "Cleanup mock rerun changed files must equal the allowlisted artifact."
  }
  Assert-True $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
  Assert-True $result.diff_patch_non_empty "diff_patch_non_empty"
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $cleanup = Get-Content -Raw -LiteralPath (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-report.json") | ConvertFrom-Json
  Assert-True $cleanup.cleanup_requested "cleanup.cleanup_requested"
  Assert-True $cleanup.cleanup_authorization_phrase_matched "cleanup.cleanup_authorization_phrase_matched"
  Assert-True $cleanup.cleanup_completed "cleanup.cleanup_completed"
  if ([string]$cleanup.cleanup_method -notmatch "git_worktree_remove_force") { throw "cleanup_method did not use git worktree remove." }
  Assert-TokenPrintedFalse $cleanup
} finally {
  if (Test-Path -LiteralPath $worktreePath) {
    git worktree remove --force $worktreePath 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-cleanup-mock-rerun"
