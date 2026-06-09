. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate"
if (-not $gate.can_run_pilot) { throw "Pilot gate should pass with classified Codex launcher: $($gate.blockers -join ',')" }
if (-not $gate.launcher_metadata) { throw "Expected launcher metadata." }
if ($gate.launcher_metadata.launcher_kind -eq "ps1" -and $gate.launcher_metadata.host_executable_name -notmatch "pwsh|powershell") {
  throw "ps1 launcher must be hosted by PowerShell."
}
if ($gate.launcher_metadata.launcher_kind -in @("cmd", "bat") -and $gate.launcher_metadata.host_executable_name -ne "cmd.exe") {
  throw "cmd/bat launcher must be hosted by cmd.exe."
}
Write-ManagedModeSmokeResult "managed-mode-pilot-codex-launcher-classified"
