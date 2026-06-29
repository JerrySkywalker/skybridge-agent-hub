. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-no-release" `
  -Actions @("preview", "start-fixture") `
  -Reset `
  -StartConfirm $OperatorTuiStartConfirmation

Assert-False $result.report.release_created "release_created"
Assert-False $result.report.tag_created "tag_created"
Assert-False $result.report.asset_uploaded "asset_uploaded"
Assert-False $result.state.release_created "state.release_created"
Assert-False $result.state.tag_created "state.tag_created"
Assert-False $result.state.asset_uploaded "state.asset_uploaded"

Complete-Smoke "operator-tui-single-step-no-release"
