[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-timeout-fixture"
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
  "-Mode", "codex-local-diff-timeout-fixture",
  "-OutputDir", $outputDir,
  "-CodexTimeoutSeconds", "1"
)

try {
  if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.v4") { throw "Unexpected schema." }
  if ([string]$result.demo_result -ne "blocked") { throw "Timeout fixture must block." }
  Assert-True $result.fixture_mode "fixture_mode"
  Assert-True $result.codex_called "codex_called"
  if ([int]$result.codex_call_count -ne 1) { throw "codex_call_count must be 1." }
  Assert-True $result.codex_timed_out "codex_timed_out"
  if ([string]$result.codex_failure_class -ne "codex_exec_timeout_no_artifact") {
    throw "Unexpected codex_failure_class: $($result.codex_failure_class)"
  }
  Assert-False $result.target_artifact_exists "target_artifact_exists"
  Assert-False $result.diff_patch_non_empty "diff_patch_non_empty"
  Assert-False $result.pr_created "pr_created"
  Assert-False $result.branch_pushed "branch_pushed"
  Assert-False $result.commit_created "commit_created"
  Assert-TokenPrintedFalse $result

  $diagnostics = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-execution-diagnostics.json") | ConvertFrom-Json
  Assert-True $diagnostics.codex_timed_out "diagnostics.codex_timed_out"
  Assert-True $diagnostics.codex_process_killed "diagnostics.codex_process_killed"
  Assert-False $diagnostics.codex_artifact_created_before_timeout "diagnostics.codex_artifact_created_before_timeout"
  Assert-TokenPrintedFalse $diagnostics

  $classification = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-failure-classification.json") | ConvertFrom-Json
  if ([string]$classification.codex_failure_class -ne "codex_exec_timeout_no_artifact") {
    throw "Failure classification artifact did not record timeout."
  }
  Assert-TokenPrintedFalse $classification
} finally {
  if (Test-Path -LiteralPath (Join-Path $resolvedOutputDir "worktree")) {
    git worktree remove --force (Join-Path $resolvedOutputDir "worktree") 2>$null
  }
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-timeout-classification"
