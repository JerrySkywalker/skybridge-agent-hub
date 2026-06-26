. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @("-Command", "status")

Assert-True $result.ok "desktop_installer_post_release_status_ok"
if ($result.schema -ne "skybridge.desktop_installer_post_release_smoke.v1") {
  throw "Unexpected schema."
}
Assert-False $result.release_created "release_created"
Assert-False $result.release_updated "release_updated"
Assert-False $result.tag_created "tag_created"
Assert-False $result.tag_moved "tag_moved"
Assert-False $result.silent_install_used "silent_install_used"
Assert-False $result.windows_security_bypass "windows_security_bypass"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-status"
