. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-review-preview" `
  -Actions @("generate", "validate", "review-preview") `
  -Reset

Assert-True $result.report.candidate_generated "candidate_generated"
Assert-True $result.report.candidate_validated "candidate_validated"
if ($result.state.review_status -ne "previewed") { throw "Review preview must leave review_status=previewed." }
Assert-False $result.report.candidate_reviewed "candidate_reviewed"
Assert-False $result.report.candidate_approved_for_append "candidate_approved_for_append"
Assert-False $result.report.append_performed "append_performed"

Complete-Smoke "operator-tui-candidate-review-preview"
