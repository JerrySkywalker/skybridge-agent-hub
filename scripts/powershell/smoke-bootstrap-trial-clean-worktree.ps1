param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-trial-goal201-common.ps1" -Scenario clean-worktree -Json:$Json
