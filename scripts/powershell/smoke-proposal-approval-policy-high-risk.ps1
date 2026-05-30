[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "approval-policy-high-risk" -Json:$Json
exit $LASTEXITCODE
