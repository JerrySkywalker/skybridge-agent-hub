. "$PSScriptRoot\smoke-productization-common.ps1"
$status = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "status")
if ($status.schema -ne "skybridge.local_session.v1") { throw "schema mismatch" }
Assert-False $status.token_printed "token_printed"
foreach ($capability in @("codex_worker", "workunit_apply", "task_claim", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")) {
  if ($status.disabled_capabilities -notcontains $capability) { throw "Missing disabled capability: $capability" }
}
Complete-Smoke "local-session-contract"
