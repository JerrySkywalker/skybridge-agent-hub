. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$state = Invoke-BoincManagerJson "status"
if ($state.control_surface.completed_bootstrap_trial.final_state -ne "bootstrap_trial_completed") { throw "Bootstrap completed final state missing." }
if ($state.control_surface.completed_bootstrap_trial.task_pr_url -notmatch "/pull/124$") { throw "Task PR #124 reference missing." }
$desktop = Get-Content (Join-Path $PSScriptRoot "../../apps/desktop/src/main.tsx") -Raw
$web = Get-Content (Join-Path $PSScriptRoot "../../apps/web/src/main.tsx") -Raw
if ($desktop -notmatch "Completed bootstrap trial" -or $web -notmatch "Task PR / finalizer") { throw "Bootstrap completed badge/reference missing in UI." }
Write-SmokeResult "boinc-manager-bootstrap-completed-badge"
