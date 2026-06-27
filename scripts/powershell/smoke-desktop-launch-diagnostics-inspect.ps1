. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-launch-diagnostics.ps1" @("-Command", "inspect")

if ($result.schema -ne "skybridge.desktop_launch_diagnostics.v1") {
  throw "Unexpected schema: $($result.schema)"
}
Assert-True $result.ok "desktop_launch_diagnostics_inspect_ok"
Assert-True $result.windows_subsystem_configured "windows_subsystem_configured"
Assert-True $result.hidden_powershell_configured "hidden_powershell_configured"
Assert-True $result.status_failures_nonfatal "status_failures_nonfatal"
Assert-False $result.launch_attempted "launch_attempted"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-launch-diagnostics-inspect"
