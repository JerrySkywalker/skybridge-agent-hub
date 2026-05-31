[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-gate-missing-dependency" -Json:$Json
exit $LASTEXITCODE
