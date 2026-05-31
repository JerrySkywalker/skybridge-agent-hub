[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "gate-no-secrets" -Json:$Json
exit $LASTEXITCODE
