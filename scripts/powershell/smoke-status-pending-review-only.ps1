[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-status-fixture.ps1" -Scenario "pending-review-only" -Json:$Json
exit $LASTEXITCODE
