[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-mock-success"
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
  "-Mode", "codex-local-diff-mock-success",
  "-OutputDir", $outputDir,
  "-CodexTimeoutSeconds", "30"
)

try {
  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v4") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "pass") { throw "Mock success did not pass." }
  Assert-True $result.fixture_mode "fixture_mode"
  Assert-True $result.codex_available "codex_available"
  Assert-True $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 1) { throw "codex_call_count must be 1." }
  Assert-False $result.codex_timed_out "codex_timed_out"
  if ([string]$result.codex_failure_class -ne "none") { throw "codex_failure_class must be none." }
  if (@($result.changed_files).Count -ne 1 -or [string]$result.changed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
    throw "Mock success changed files must equal the allowlisted artifact."
  }
  Assert-True $result.docs_only_allowlist_passed "docs_only_allowlist_passed"
  Assert-True $result.diff_patch_non_empty "diff_patch_non_empty"
  Assert-True $result.target_artifact_exists "target_artifact_exists"
  if ([int64]$result.target_artifact_size_bytes -le 0) { throw "target_artifact_size_bytes must be positive." }
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  foreach ($file in @(
    "codex-local-diff-report.json",
    "codex-local-diff-report.md",
    "codex-local-diff-stdout.log",
    "codex-local-diff-stderr.log",
    "codex-local-diff-execution-diagnostics.json",
    "codex-local-diff-failure-classification.json",
    "codex-local-diff.patch"
  )) {
    Assert-FileExists "$outputDir/$file"
  }

  $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-execution-diagnostics.json") | ConvertFrom-Json
  Assert-True $diagnostics.codex_available "diagnostics.codex_available"
  Assert-False $diagnostics.codex_timed_out "diagnostics.codex_timed_out"
  Assert-TokenPrintedFalse $diagnostics
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-mock-success"
