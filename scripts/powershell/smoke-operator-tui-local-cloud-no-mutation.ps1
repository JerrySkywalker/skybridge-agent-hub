. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-local-cloud-no-mutation" "local-cloud" ".agent/tmp/operator-tui/local-cloud"

if ($result.state.mode -ne "local-cloud") { throw "Operator TUI state must use local-cloud mode." }
Assert-OperatorTuiNoMutation -State $result.state -Report $result.report

Complete-Smoke "operator-tui-local-cloud-no-mutation"
