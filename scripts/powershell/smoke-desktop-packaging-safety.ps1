. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-packaging-readiness.ps1" @("-Command", "audit")

Assert-True $result.ok "desktop_packaging_safety_ok"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-TokenPrintedFalse $result

$warningText = @($result.warnings) -join "`n"
if ($warningText -notmatch "desktop_safety_static_scan_only") {
  throw "Expected static safety scan warning."
}

Complete-Smoke "desktop-packaging-safety"
