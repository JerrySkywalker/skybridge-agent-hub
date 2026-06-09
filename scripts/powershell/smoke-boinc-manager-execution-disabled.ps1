. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$state = Invoke-BoincManagerJson "status"
if ($state.local_worker_supervisor_state.can_claim_tasks -ne $false) { throw "Worker claim must be disabled." }
if ($state.local_worker_supervisor_state.can_execute_tasks -ne $false) { throw "Worker execution must be disabled." }
if ($state.workunit_preview_plan.would_create_tasks -or $state.workunit_preview_plan.would_claim_tasks -or $state.workunit_preview_plan.would_execute_tasks -or $state.workunit_preview_plan.would_create_prs) { throw "Preview plan must not create/claim/execute/PR." }
Write-SmokeResult "boinc-manager-execution-disabled"
