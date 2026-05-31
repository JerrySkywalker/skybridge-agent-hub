[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-with-gate-requires-apply" -Json:$Json
exit $LASTEXITCODE
