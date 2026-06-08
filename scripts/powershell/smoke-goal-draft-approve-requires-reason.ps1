[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-goal-draft-review-fixture.ps1" -Scenario approve-requires-reason -Json:$Json
