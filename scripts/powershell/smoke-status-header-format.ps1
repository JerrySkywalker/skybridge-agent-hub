[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "header-format" -Json:$Json
exit $LASTEXITCODE
