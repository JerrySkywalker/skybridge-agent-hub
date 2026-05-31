[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-gate-active-task-block" -Json:$Json
exit $LASTEXITCODE
