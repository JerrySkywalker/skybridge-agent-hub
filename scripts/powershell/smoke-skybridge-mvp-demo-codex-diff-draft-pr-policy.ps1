[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-draft-pr"
$reportPath = Join-Path $RepoRoot "$outputDir/codex-draft-pr-report.json"
Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-diff-draft-pr-preview", "-OutputDir", $outputDir) | Out-Null

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$branchPlan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-branch-plan.json") | ConvertFrom-Json
$allowlist = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-allowlist-check.json") | ConvertFrom-Json
$metadata = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-pr-metadata.json") | ConvertFrom-Json
$source = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-source-diff-validation.json") | ConvertFrom-Json
$preflight = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-preflight.json") | ConvertFrom-Json

Assert-True $report.branch_policy_passed "report.branch_policy_passed"
Assert-True $report.docs_only_allowlist_passed "report.docs_only_allowlist_passed"
Assert-True $branchPlan.branch_policy_passed "branch_plan.branch_policy_passed"
Assert-True $branchPlan.branch_name_recorded_before_mutation "branch_name_recorded_before_mutation"
Assert-True $branchPlan.one_branch_max "one_branch_max"
if ([string]$branchPlan.branch_name -notmatch "^demo/mg372e2-codex-draft-pr-[0-9]{8}-[A-Za-z0-9]{7}$") { throw "Branch plan does not match MG372E2 policy." }
Assert-True $allowlist.docs_only_allowlist_passed "allowlist.docs_only_allowlist_passed"
if (@($allowlist.allowed_files).Count -ne 1 -or [string]$allowlist.allowed_files[0] -ne "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md") {
  throw "Unexpected Codex draft PR allowlist."
}
Assert-True $metadata.draft "metadata.draft"
Assert-False $metadata.auto_merge_enabled "metadata.auto_merge_enabled"
Assert-True $source.source_validation_passed "source.source_validation_passed"
Assert-True $preflight.no_existing_demo_pr "preflight.no_existing_demo_pr"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-codex-diff-draft-pr-policy"
