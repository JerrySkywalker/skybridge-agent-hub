[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "defer" -Json:$Json
exit $LASTEXITCODE
