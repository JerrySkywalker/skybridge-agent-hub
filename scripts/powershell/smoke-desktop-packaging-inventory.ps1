. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-packaging-readiness.ps1" @("-Command", "inventory")

Assert-True $result.ok "desktop_packaging_inventory_ok"
if ($result.desktop_root -ne "apps/desktop") { throw "Unexpected desktop root: $($result.desktop_root)" }
if ($result.framework -notmatch "Tauri") { throw "Desktop framework was not detected as Tauri." }
if ($result.package_manager -ne "pnpm") { throw "Expected pnpm package manager." }
if (-not $result.build_command_detected) { throw "Desktop build command was not detected." }
if (-not $result.package_command_detected) { throw "Desktop package command was not detected." }
if ($result.app_name -ne "SkyBridge Desktop") { throw "Unexpected app name: $($result.app_name)" }
if ($result.app_identifier -ne "space.jerryskywalker.skybridge.desktop") { throw "Unexpected app identifier: $($result.app_identifier)" }
if ($result.app_version -ne "0.1.0") { throw "Unexpected app version: $($result.app_version)" }
Assert-True $result.windows_packaging_config_present "windows_packaging_config_present"
Assert-True $result.icon_config_present "icon_config_present"
Assert-False $result.signing_config_present "signing_config_present"
Assert-True $result.unsigned_installer_expected "unsigned_installer_expected"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-packaging-inventory"
