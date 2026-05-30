[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "active-only-empty" -Json:$Json
exit $LASTEXITCODE
