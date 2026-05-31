[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "hermes-gate-invalid-json" -Json:$Json
exit $LASTEXITCODE
