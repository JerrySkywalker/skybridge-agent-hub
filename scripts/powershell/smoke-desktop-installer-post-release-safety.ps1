. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @("-Command", "safe-summary")

Assert-True $result.ok "desktop_installer_post_release_safety_ok"
Assert-False $result.release_created "release_created"
Assert-False $result.release_updated "release_updated"
Assert-False $result.tag_created "tag_created"
Assert-False $result.tag_moved "tag_moved"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.silent_install_used "silent_install_used"
Assert-False $result.windows_security_bypass "windows_security_bypass"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-safety"
