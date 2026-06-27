. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "status", "-Fixture")

if ($result.schema -ne "skybridge.tool_provider.v1") { throw "Unexpected schema." }
if ($result.provider_inventory -ne "fixture_status") { throw "Unexpected status inventory mode." }
Assert-False $result.execution_allowed "execution_allowed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-status"
