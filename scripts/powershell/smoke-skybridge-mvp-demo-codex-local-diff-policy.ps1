[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-policy-fixture"
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
$reportPath = Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-local-diff-policy-fixture", "-OutputDir", $outputDir)

try {
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $allowlist = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-allowlist-check.json") | ConvertFrom-Json
  $changed = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-changed-files.json") | ConvertFrom-Json
  $preflight = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-preflight.json") | ConvertFrom-Json

  if ([string]$report.demo_result -ne "blocked") { throw "Policy fixture must block." }
  Assert-False $report.docs_only_allowlist_passed "report.docs_only_allowlist_passed"
  Assert-False $allowlist.docs_only_allowlist_passed "allowlist.docs_only_allowlist_passed"
  if (@($allowlist.allowed_files).Count -ne 1 -or [string]$allowlist.allowed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
    throw "Unexpected Codex local diff allowlist."
  }
  if (@($changed.changed_files).Count -ne 1 -or [string]$changed.changed_files[0] -ne "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md") {
    throw "Unexpected policy fixture changed files."
  }
  if (@($allowlist.unexpected_files).Count -ne 1 -or [string]$allowlist.unexpected_files[0] -ne "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md") {
    throw "Expected non-allowlisted path was not reported."
  }
  if (@($report.blockers) -notcontains "docs_only_allowlist_failed_after_codex") {
    throw "Expected allowlist blocker missing."
  }
  Assert-True $preflight.preflight_passed "preflight.preflight_passed"
  Assert-True $preflight.git_available "preflight.git_available"
  Assert-True $report.git_index_collector_used "git_index_collector_used"
  Assert-False $report.hash_comparison_used "hash_comparison_used"
  Assert-False $report.codex_called "codex_called"
  Assert-False $report.pr_created "report.pr_created"
  Assert-False $report.branch_pushed "report.branch_pushed"
  Assert-False $report.commit_created "report.commit_created"
  Assert-TokenPrintedFalse $report
  Assert-TokenPrintedFalse $result
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-policy"
