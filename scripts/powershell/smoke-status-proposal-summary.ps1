[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "proposal-summary" -Json:$Json
exit $LASTEXITCODE
