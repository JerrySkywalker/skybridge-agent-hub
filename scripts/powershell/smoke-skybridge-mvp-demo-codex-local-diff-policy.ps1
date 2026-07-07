[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$reportPath = Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-local-diff-preview", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$allowlist = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-allowlist-check.json") | ConvertFrom-Json
$changed = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-changed-files.json") | ConvertFrom-Json
$preflight = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-preflight.json") | ConvertFrom-Json

Assert-True $report.docs_only_allowlist_passed "report.docs_only_allowlist_passed"
Assert-True $allowlist.docs_only_allowlist_passed "allowlist.docs_only_allowlist_passed"
if (@($allowlist.allowed_files).Count -ne 1 -or [string]$allowlist.allowed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
  throw "Unexpected Codex local diff allowlist."
}
if (@($changed.changed_files).Count -ne 1 -or [string]$changed.changed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
  throw "Unexpected planned changed files."
}
Assert-True $preflight.preflight_passed "preflight.preflight_passed"
Assert-True $preflight.git_available "preflight.git_available"
Assert-False $report.pr_created "report.pr_created"
Assert-False $report.branch_pushed "report.branch_pushed"
Assert-False $report.commit_created "report.commit_created"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-policy"
