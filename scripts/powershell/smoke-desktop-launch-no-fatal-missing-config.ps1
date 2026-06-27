. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-launch-diagnostics.ps1" @("-Command", "inspect")

Assert-True $result.ok "desktop_launch_no_fatal_missing_config_ok"
Assert-True $result.status_failures_nonfatal "status_failures_nonfatal"
if (@($result.blockers) -contains "status_bridge_failure_may_be_fatal") {
  throw "Desktop status bridge failures must remain nonfatal."
}
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-launch-no-fatal-missing-config"
