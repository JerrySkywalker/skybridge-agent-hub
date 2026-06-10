. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate"
if ($gate.launcher_metadata.command_profile_id -ne "profile_workspace_write_workdir") { throw "Managed-mode pilot must prefer workspace-write profile." }
if ($gate.launcher_metadata.command_class -ne "codex_exec_workspace_write_workdir_stdin_discard_output") { throw "Unexpected command class." }
Assert-ManagedModeSafeJson $gate
Write-ManagedModeSmokeResult "managed-mode-codex-invocation-prefers-proven-workspace-write"
