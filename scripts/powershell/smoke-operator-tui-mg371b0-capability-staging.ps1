$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "capability-staging" -Reset

Assert-True $result.report.fake_provider_used "fake_provider_used"
Assert-True $result.provider.fake_provider_executed "provider fake_provider_executed"
Assert-True $result.provider.fake_branch_metadata_recorded "provider fake_branch_metadata_recorded"
Assert-True $result.provider.fake_pr_metadata_recorded "provider fake_pr_metadata_recorded"
Assert-True $result.authorization.authorization_phrase_matched_for_future_flow "authorization_phrase_matched_for_future_flow"
Assert-False $result.authorization.phrase_used_for_real_mutation "phrase_used_for_real_mutation"
Assert-True $result.branch.branch_name_valid "branch_name_valid"
Assert-True $result.allowlist.docs_only_allowlist_passed "docs_only_allowlist_passed"
Assert-True $result.pr.draft_pr "draft_pr"
Assert-False $result.pr.auto_merge "auto_merge"
Assert-False $result.pr.release_tag_assets "release_tag_assets"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b0-capability-staging"
