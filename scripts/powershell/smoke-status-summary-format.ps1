[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "summary-format" -Json:$Json
exit $LASTEXITCODE
