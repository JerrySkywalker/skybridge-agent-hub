. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$state = Invoke-BoincManagerJson "status"
foreach ($field in @("schema", "project_id", "product_name", "control_surface", "local_resident_state", "local_worker_supervisor_state", "local_resource_policy", "workunit_preview_plan", "bounded_queue_readiness", "active_holds", "next_safe_action", "token_printed")) {
  if (-not ($state.PSObject.Properties.Name -contains $field)) { throw "Missing BOINC manager state field: $field" }
}
if ($state.schema -ne "skybridge.boinc_manager_state.v1") { throw "Unexpected manager state schema." }
if ($state.control_surface.schema -ne "skybridge.boinc_control_surface.v1") { throw "Unexpected control surface schema." }
Write-SmokeResult "boinc-manager-state-contract"
