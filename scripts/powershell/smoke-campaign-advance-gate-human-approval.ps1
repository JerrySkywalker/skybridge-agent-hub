[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-gate-human-approval" -Json:$Json
exit $LASTEXITCODE
