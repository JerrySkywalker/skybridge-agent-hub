. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$state = Invoke-BoincManagerJson "status"
if ($state.bounded_queue_readiness.can_start_bounded_queue -ne $false) { throw "can_start_bounded_queue must be false." }
if ($state.bounded_queue_readiness.start_bounded_queue_apply_available -ne $false) { throw "bounded queue apply must be unavailable." }
$blocked = @($state.control_surface.action_matrix.disabled | ForEach-Object { $_.action })
if ($blocked -notcontains "bounded_queue_apply") { throw "bounded_queue_apply must be disabled in action matrix." }
Write-SmokeResult "boinc-manager-no-bounded-queue-apply"
