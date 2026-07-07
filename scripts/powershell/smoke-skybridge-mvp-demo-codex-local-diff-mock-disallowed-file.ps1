[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-mock-disallowed-file"
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
  "-Mode", "codex-local-diff-mock-disallowed-file",
  "-OutputDir", $outputDir,
  "-CodexTimeoutSeconds", "30"
)

try {
  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v3") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "blocked") { throw "Disallowed-file fixture must block." }
  Assert-True $result.fixture_mode "fixture_mode"
  Assert-True $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 1) { throw "codex_call_count must be 1." }
  if ([string]$result.codex_failure_class -ne "codex_modified_disallowed_files") {
    throw "Unexpected codex_failure_class: $($result.codex_failure_class)"
  }
  Assert-False $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
  if (@($result.changed_files) -notcontains "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
    throw "Changed files missing allowed artifact."
  }
  if (@($result.changed_files) -notcontains "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md") {
    throw "Changed files missing disallowed artifact."
  }
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $allowlist = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-allowlist-check.json") | ConvertFrom-Json
  Assert-False $allowlist.docs_only_allowlist_passed "allowlist.docs_only_allowlist_passed"
  if (@($allowlist.unexpected_files) -notcontains "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md") {
    throw "Allowlist artifact did not report the offending path."
  }
  Assert-TokenPrintedFalse $allowlist
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-mock-disallowed-file"
