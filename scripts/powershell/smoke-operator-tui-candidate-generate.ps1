. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-generate" `
  -Actions @("generate") `
  -Reset

Assert-True $result.report.candidate_generated "candidate_generated"
Assert-True $result.report.candidate_validated "candidate_validated"
Assert-False $result.report.candidate_reviewed "candidate_reviewed"
Assert-False $result.report.candidate_approved_for_append "candidate_approved_for_append"
Assert-False $result.report.append_performed "append_performed"
if ([string]$result.state.candidate_path -notmatch [regex]::Escape(".agent/tmp/hermes-planner-provider/operator-tui-candidate-flow/")) {
  throw "Candidate path must stay under Hermes fixture tmp output."
}
if ([string]$result.state.candidate_hash -notmatch "^[a-f0-9]{64}$") { throw "Candidate hash must be a SHA-256 hex digest." }

Complete-Smoke "operator-tui-candidate-generate"
