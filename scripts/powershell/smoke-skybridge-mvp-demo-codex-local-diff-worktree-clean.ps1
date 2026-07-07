[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-worktree-clean"
$resolvedOutputDir = Join-Path $RepoRoot $outputDir
$tmpRoot = Join-Path $RepoRoot ".agent/tmp"
if (-not ([System.IO.Path]::GetFullPath($resolvedOutputDir).StartsWith([System.IO.Path]::GetFullPath($tmpRoot)))) {
  throw "Refusing to clean output outside .agent/tmp."
}
if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
  git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
}
if (Test-Path -LiteralPath $resolvedOutputDir) {
  Remove-Item -LiteralPath $resolvedOutputDir -Recurse -Force
}

$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-local-diff-worktree-clean",
  "-OutputDir", $outputDir
)

try {
  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v2") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "pass") { throw "Worktree clean fixture did not pass." }
  Assert-True $result.isolated_workspace_used "isolated_workspace_used"
  if ([string]$result.workspace_setup_method -ne "git_worktree") { throw "workspace_setup_method must be git_worktree." }
  Assert-True $result.workspace_clean_before_codex "workspace_clean_before_codex"
  Assert-True $result.git_index_collector_used "git_index_collector_used"
  Assert-False $result.hash_comparison_used "hash_comparison_used"
  Assert-False $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 0) { throw "codex_call_count must be 0." }
  if (@($result.changed_files).Count -ne 0) { throw "Fresh worktree must have no changed files." }
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-collector-diagnostics.json") | ConvertFrom-Json
  Assert-True $diagnostics.workspace_clean_before_codex "diagnostics.workspace_clean_before_codex"
  if (@($diagnostics.pre_codex_status_porcelain).Count -ne 0) { throw "pre-Codex status must be clean." }
  Assert-False $diagnostics.hash_comparison_used "diagnostics.hash_comparison_used"
  Assert-True $diagnostics.git_index_collector_used "diagnostics.git_index_collector_used"
  Assert-TokenPrintedFalse $diagnostics
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-worktree-clean"
