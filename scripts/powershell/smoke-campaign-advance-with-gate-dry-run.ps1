[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-with-gate-dry-run" -Json:$Json
exit $LASTEXITCODE
