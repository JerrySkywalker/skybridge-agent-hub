[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff/stale-detect-smoke"
$resolvedOutputDir = Join-Path $RepoRoot $outputDir
$worktreePath = Join-Path $resolvedOutputDir "worktree"
$tmpRoot = Join-Path $RepoRoot ".agent/tmp/skybridge-mvp-codex-diff"
if (-not ([System.IO.Path]::GetFullPath($resolvedOutputDir).StartsWith([System.IO.Path]::GetFullPath($tmpRoot)))) {
  throw "Refusing to prepare stale worktree outside .agent/tmp/skybridge-mvp-codex-diff."
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
    "-Mode", "codex-local-diff-preview",
    "-OutputDir", $outputDir
  )

  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v4") { throw "Unexpected schema." }
  if ([string]$result.validation_status -ne "preview_passed") { throw "Stale-worktree preview did not pass." }
  Assert-True $result.stale_worktree_detected "stale_worktree_detected"
  Assert-True $result.would_clean_existing_worktree "would_clean_existing_worktree"
  Assert-False $result.cleanup_requested "cleanup_requested"
  Assert-False $result.cleanup_completed "cleanup_completed"
  Assert-False $result.codex_called "codex_called"
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $cleanup = Get-Content -Raw -LiteralPath (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-report.json") | ConvertFrom-Json
  Assert-True $cleanup.stale_worktree_detected "cleanup.stale_worktree_detected"
  Assert-True $cleanup.stale_worktree_registered "cleanup.stale_worktree_registered"
  Assert-False $cleanup.cleanup_requested "cleanup.cleanup_requested"
  Assert-TokenPrintedFalse $cleanup
} finally {
  if (Test-Path -LiteralPath $worktreePath) {
    git worktree remove --force $worktreePath 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-stale-worktree-detect"
