. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-staging.ps1" @("-Command", "preview")

if ($result.schema -ne "skybridge.desktop_installer_staging.v1") {
  throw "Unexpected schema: $($result.schema)"
}
Assert-True $result.ok "desktop_installer_staging_preview_ok"
Assert-False $result.build_attempted "build_attempted"
Assert-False $result.package_attempted "package_attempted"
Assert-False $result.release_created "release_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-False $result.tag_created "tag_created"
Assert-False $result.tag_moved "tag_moved"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-staging-preview"
