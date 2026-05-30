[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "show-proposals" -Json:$Json
exit $LASTEXITCODE
