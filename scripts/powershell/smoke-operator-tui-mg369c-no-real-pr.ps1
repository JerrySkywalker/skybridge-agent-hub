$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg369cDocsPrSimulation

Assert-OperatorTuiMg369cNoRealPr `
  -Report $result.report `
  -Simulation $result.simulation `
  -Safety $result.safety
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg369c-no-real-pr"
