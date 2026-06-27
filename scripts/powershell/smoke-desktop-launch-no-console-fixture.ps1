. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-launch-diagnostics.ps1" @("-Command", "inspect")

Assert-True $result.ok "desktop_launch_no_console_fixture_ok"
Assert-True $result.windows_subsystem_configured "windows_subsystem_configured"
Assert-True $result.hidden_powershell_configured "hidden_powershell_configured"
if (@($result.blockers) -contains "windows_subsystem_missing") {
  throw "Windows subsystem must be configured for release builds."
}
if (@($result.blockers) -contains "visible_status_bridge_shell") {
  throw "Passive status bridge shell must be hidden."
}
Assert-False $result.unexpected_console_window_detected "unexpected_console_window_detected"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-launch-no-console-fixture"
