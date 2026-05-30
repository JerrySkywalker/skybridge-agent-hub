[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "summary-counts" -Json:$Json
exit $LASTEXITCODE
