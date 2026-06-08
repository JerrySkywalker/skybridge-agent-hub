[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-goal-draft-review-fixture.ps1" -Scenario import-no-execution -Json:$Json
