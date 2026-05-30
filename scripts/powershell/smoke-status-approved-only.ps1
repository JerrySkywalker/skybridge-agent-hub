[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "approved-only" -Json:$Json
exit $LASTEXITCODE
