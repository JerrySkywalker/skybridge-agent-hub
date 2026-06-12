. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
$preview = Invoke-BoincV1PreviewJson -Command "two-workunit-preview" -SimulateOpenReview
Assert-True ([bool]$preview.blocked_by_open_review) "Preview must block on open review hold."
Assert-Equal $preview.blocked_reason "blocked_by_open_review" "Expected blocked_by_open_review reason."
$gate = Invoke-BoincV1PreviewJson -Command "apply-gate" -SimulateOpenReview
Assert-True ($gate.blockers -contains "blocked_by_open_review") "Apply gate must include open review blocker."
Write-SmokeResult "boinc-v1-blocks-when-open-pr-hold"
