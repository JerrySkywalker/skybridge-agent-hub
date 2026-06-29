. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-append-preview" `
  -Actions @("generate", "validate", "review-approve", "append-preview") `
  -Reset `
  -ReviewConfirm $OperatorTuiReviewConfirmation

Assert-True $result.report.candidate_generated "candidate_generated"
Assert-True $result.report.candidate_validated "candidate_validated"
Assert-True $result.report.candidate_reviewed "candidate_reviewed"
Assert-True $result.report.candidate_approved_for_append "candidate_approved_for_append"
Assert-True $result.report.append_previewed "append_previewed"
Assert-False $result.report.append_performed "append_performed"
Assert-True $result.report.append_attempted "append_attempted"
Assert-True $result.report.approval_attempted "approval_attempted"

Complete-Smoke "operator-tui-candidate-append-preview"
