. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-no-auto-merge" `
  -Actions @("preview", "start-fixture") `
  -Reset `
  -StartConfirm $OperatorTuiStartConfirmation

Assert-False $result.report.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.report.merge_performed "merge_performed"
Assert-False $result.report.deploy_triggered "deploy_triggered"
Assert-False $result.state.auto_merge_enabled "state.auto_merge_enabled"
Assert-False $result.state.merge_performed "state.merge_performed"
Assert-False $result.state.deploy_triggered "state.deploy_triggered"

Complete-Smoke "operator-tui-single-step-no-auto-merge"
