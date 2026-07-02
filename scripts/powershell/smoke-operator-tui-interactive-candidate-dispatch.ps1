. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-candidate-dispatch" `
  -Scenario "candidate-dispatch" `
  -Reset

Assert-True $result.report.candidate_actions_dispatchable "candidate_actions_dispatchable"

$candidateReportPath = Join-Path $RepoRoot "$($result.output_dir)/operator-tui-candidate-report.json"
if (-not (Test-Path -LiteralPath $candidateReportPath -PathType Leaf)) { throw "Missing candidate dispatch report." }
$candidateReport = Get-Content -Raw -LiteralPath $candidateReportPath | ConvertFrom-Json
Assert-True $candidateReport.candidate_generated "candidate_generated"
Assert-True $candidateReport.candidate_validated "candidate_validated"
Assert-True $candidateReport.candidate_reviewed "candidate_reviewed"
Assert-True $candidateReport.append_performed "append_performed"
Assert-False $candidateReport.execution_started "candidate execution_started"
Assert-False $candidateReport.branch_created "candidate branch_created"
Assert-False $candidateReport.pr_created "candidate pr_created"
Assert-TokenPrintedFalse $candidateReport

Complete-Smoke "operator-tui-interactive-candidate-dispatch"
