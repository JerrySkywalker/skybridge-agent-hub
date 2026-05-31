[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "hermes-gate-human-approval" -Json:$Json
exit $LASTEXITCODE
