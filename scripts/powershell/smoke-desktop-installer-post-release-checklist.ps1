. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @("-Command", "checklist")

Assert-True $result.ok "desktop_installer_post_release_checklist_ok"
Assert-True $result.install_manual_steps_required "install_manual_steps_required"
Assert-False $result.installer_opened "installer_opened"
Assert-False $result.app_launch_attempted "app_launch_attempted"
Assert-False $result.silent_install_used "silent_install_used"
Assert-False $result.windows_security_bypass "windows_security_bypass"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-checklist"
