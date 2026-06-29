. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-validate" `
  -Actions @("generate", "validate") `
  -Reset

Assert-True $result.report.candidate_generated "candidate_generated"
Assert-True $result.report.candidate_validated "candidate_validated"
if ($result.state.validation_result -ne "valid") { throw "Candidate validation_result must be valid." }
if (@($result.state.validation_blockers).Count -ne 0) { throw "Candidate validation must have no blockers." }
Assert-False $result.report.append_performed "append_performed"

Complete-Smoke "operator-tui-candidate-validate"
