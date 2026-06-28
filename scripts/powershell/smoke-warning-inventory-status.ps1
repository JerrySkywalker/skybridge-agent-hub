. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-warning-inventory.ps1" @(
  "-Command", "status"
)

if ($result.schema -ne "skybridge.warning_inventory.v1") { throw "Unexpected warning inventory schema." }
if (@($result.known_warnings).Count -ne 2) { throw "Expected exactly two known warnings." }
Assert-True $result.warning_inventory_doc_present "warning_inventory_doc_present"
Assert-True $result.warnings_are_non_failing "warnings_are_non_failing"
Assert-False $result.warnings_suppressed "warnings_suppressed"
Assert-False $result.ci_threshold_changed "ci_threshold_changed"
Assert-False $result.workflow_changed "workflow_changed"
Assert-False $result.build_config_changed "build_config_changed"
Assert-False $result.deploy_config_changed "deploy_config_changed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.queue_runner_started "queue_runner_started"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "warning-inventory-status"
