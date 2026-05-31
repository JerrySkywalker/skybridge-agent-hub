[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "campaign-gate-human-approval-required" -Json:$Json
exit $LASTEXITCODE
