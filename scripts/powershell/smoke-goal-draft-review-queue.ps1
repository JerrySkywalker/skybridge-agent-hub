[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-goal-draft-review-fixture.ps1" -Scenario queue -Json:$Json
