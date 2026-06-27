. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-launch-diagnostics.ps1" @("-Command", "status")

if ($result.schema -ne "skybridge.desktop_launch_diagnostics.v1") {
  throw "Unexpected schema: $($result.schema)"
}
Assert-True $result.ok "desktop_launch_diagnostics_status_ok"
Assert-False $result.launch_attempted "launch_attempted"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-launch-diagnostics-status"
