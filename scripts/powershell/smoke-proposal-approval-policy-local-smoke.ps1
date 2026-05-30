[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "approval-policy-local-smoke" -Json:$Json
exit $LASTEXITCODE
