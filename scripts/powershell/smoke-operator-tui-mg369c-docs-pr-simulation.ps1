$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg369cDocsPrSimulation -Reset

Assert-True $result.report.docs_only_pr_simulation_used "docs_only_pr_simulation_used"
Assert-True $result.report.simulated_docs_pr_completed "simulated_docs_pr_completed"
Assert-True $result.report.simulated_changed_files_docs_only "simulated_changed_files_docs_only"
if ([string]::IsNullOrWhiteSpace([string]$result.report.simulated_branch_name)) {
  throw "simulated_branch_name missing."
}
if ([string]::IsNullOrWhiteSpace([string]$result.report.simulated_pr_title)) {
  throw "simulated_pr_title missing."
}
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg369c-docs-pr-simulation"
