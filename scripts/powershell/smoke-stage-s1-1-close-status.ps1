. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-stage-s1-1-close.ps1" @(
  "-Command", "status"
)

if ($result.schema -ne "skybridge.stage_s1_1_close.v1") { throw "Unexpected stage close schema." }
if ([string]::IsNullOrWhiteSpace($result.current_commit)) { throw "current_commit must be reported." }
Assert-True $result.main_aligned "main_aligned"
Assert-True $result.cloud_health.ok "cloud_health.ok"
if ($result.cloud_version.commit_sha -ne $result.current_commit) { throw "Cloud version must match current_commit." }
Assert-True $result.cloud_parity.ok "cloud_parity.ok"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.hermes_live_called "hermes_live_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "stage-s1-1-close-status"
