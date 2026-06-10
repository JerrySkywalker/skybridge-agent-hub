. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$diagnostics = Invoke-ManagedModePilotJson "codex-invocation-diagnostics"
if ($diagnostics.version_output_persisted -ne $false -or $diagnostics.help_output_persisted -ne $false) { throw "Readonly diagnostic output must not be persisted." }
if ($diagnostics.stdout_persisted -ne $false -or $diagnostics.stderr_persisted -ne $false) { throw "Diagnostics must discard stdout and stderr." }
if ($diagnostics.command_profile_id -ne "profile_workspace_write_workdir") { throw "Diagnostics should report workspace-write selected profile." }
Assert-ManagedModeSafeJson $diagnostics
Write-ManagedModeSmokeResult "managed-mode-codex-invocation-diagnostics-no-raw-output"
