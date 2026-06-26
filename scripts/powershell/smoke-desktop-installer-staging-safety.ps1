. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-staging.ps1" @("-Command", "audit")

Assert-True $result.ok "desktop_installer_staging_safety_ok"
$warnings = @($result.warnings) -join "`n"
if ($warnings -notmatch "desktop_safety_static_scan_only") {
  throw "Expected desktop_safety_static_scan_only warning."
}
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-False $result.release_created "release_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-staging-safety"
