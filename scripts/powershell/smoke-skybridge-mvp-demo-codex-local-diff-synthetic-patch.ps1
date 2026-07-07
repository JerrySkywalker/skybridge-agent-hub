[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-synthetic-patch"
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
  "-Mode", "codex-local-diff-synthetic-patch",
  "-OutputDir", $outputDir
)

try {
  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v2") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "pass") { throw "Synthetic patch fixture did not pass." }
  Assert-True $result.isolated_workspace_used "isolated_workspace_used"
  if ([string]$result.workspace_setup_method -ne "git_worktree") { throw "workspace_setup_method must be git_worktree." }
  Assert-True $result.workspace_clean_before_codex "workspace_clean_before_codex"
  Assert-True $result.git_index_collector_used "git_index_collector_used"
  Assert-False $result.hash_comparison_used "hash_comparison_used"
  Assert-False $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 0) { throw "codex_call_count must be 0." }
  if (@($result.changed_files).Count -ne 1 -or [string]$result.changed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
    throw "Synthetic patch changed files must equal the allowlisted artifact."
  }
  Assert-True $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
  Assert-True $result.diff_patch_non_empty "diff_patch_non_empty"
  Assert-True $result.target_artifact_exists "target_artifact_exists"
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $patchPath = Join-Path $RepoRoot "$outputDir/codex-local-diff.patch"
  Assert-FileExists "$outputDir/codex-local-diff.patch"
  if ((Get-Item -LiteralPath $patchPath).Length -le 0) { throw "Synthetic patch must be non-empty." }
  $patchText = Get-Content -Raw -LiteralPath $patchPath
  if ($patchText -notmatch [regex]::Escape("docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md")) {
    throw "Synthetic patch must mention the allowed artifact path."
  }
  Assert-NoUnsafeText $patchText

  $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-collector-diagnostics.json") | ConvertFrom-Json
  Assert-True $diagnostics.patch_non_empty "diagnostics.patch_non_empty"
  Assert-True $diagnostics.target_artifact_exists "diagnostics.target_artifact_exists"
  Assert-False $diagnostics.hash_comparison_used "diagnostics.hash_comparison_used"
  Assert-True $diagnostics.git_index_collector_used "diagnostics.git_index_collector_used"
  Assert-TokenPrintedFalse $diagnostics
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-synthetic-patch"
