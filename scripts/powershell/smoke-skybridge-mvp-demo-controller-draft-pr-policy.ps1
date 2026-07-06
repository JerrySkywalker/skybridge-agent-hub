[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo-pr"
$reportPath = Join-Path $RepoRoot "$outputDir/mvp-pr-demo-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "controller-draft-pr-preview", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$branchPlan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-branch-plan.json") | ConvertFrom-Json
$allowlist = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-allowlist-check.json") | ConvertFrom-Json
$metadata = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/mvp-pr-demo-pr-metadata.json") | ConvertFrom-Json

Assert-True $report.branch_policy_passed "report.branch_policy_passed"
Assert-True $report.docs_only_allowlist_passed "report.docs_only_allowlist_passed"
Assert-True $branchPlan.branch_policy_passed "branch_plan.branch_policy_passed"
Assert-True $branchPlan.branch_name_recorded_before_mutation "branch_name_recorded_before_mutation"
Assert-True $branchPlan.one_branch_max "one_branch_max"
if ([string]$branchPlan.branch_name -notmatch "^demo/mg372b-controller-draft-pr-[0-9]{8}-[A-Za-z0-9]{7}$") { throw "Branch plan does not match MG372B policy." }
Assert-True $allowlist.docs_only_allowlist_passed "allowlist.docs_only_allowlist_passed"
if (@($allowlist.allowed_files).Count -ne 1 -or [string]$allowlist.allowed_files[0] -ne "docs/product/MG372B_CONTROLLER_DRAFT_PR_DEMO_ARTIFACT.md") {
  throw "Unexpected controller draft PR allowlist."
}
Assert-True $metadata.draft "metadata.draft"
Assert-False $metadata.auto_merge_enabled "metadata.auto_merge_enabled"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-controller-draft-pr-policy"
