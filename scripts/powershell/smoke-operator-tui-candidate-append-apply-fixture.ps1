. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-append-apply-fixture" `
  -Actions @("generate", "validate", "review-approve", "append-preview", "append-apply-fixture") `
  -Reset `
  -ReviewConfirm $OperatorTuiReviewConfirmation `
  -AppendConfirm $OperatorTuiAppendConfirmation

Assert-True $result.report.candidate_generated "candidate_generated"
Assert-True $result.report.candidate_validated "candidate_validated"
Assert-True $result.report.candidate_reviewed "candidate_reviewed"
Assert-True $result.report.candidate_approved_for_append "candidate_approved_for_append"
Assert-True $result.report.append_previewed "append_previewed"
Assert-True $result.report.append_performed "append_performed"
Assert-True $result.report.append_attempted "append_attempted"
Assert-True $result.report.approval_attempted "approval_attempted"
if ([string]::IsNullOrWhiteSpace([string]$result.report.appended_step_id)) { throw "Fixture append must report appended_step_id." }
if ($result.report.appended_campaign_id -ne "operator-tui-candidate-flow-368c") { throw "Unexpected fixture append campaign id." }

Complete-Smoke "operator-tui-candidate-append-apply-fixture"
