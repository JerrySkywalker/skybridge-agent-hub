. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$profile = Invoke-ManagedModePilotJson "codex-invocation-profile"
if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile selection." }
if ($profile.profile_ephemeral_cd.profile_id -ne "profile_ephemeral_cd") { throw "Missing ephemeral profile." }
if ($profile.profile_workspace_write_workdir.profile_id -ne "profile_workspace_write_workdir") { throw "Missing workspace-write profile." }
if ($profile.profile_readonly_smoke.profile_id -ne "profile_readonly_smoke") { throw "Missing readonly smoke profile." }
if ($profile.profile_disabled_unknown.profile_id -ne "profile_disabled_unknown") { throw "Missing disabled unknown profile." }
Assert-ManagedModeSafeJson $profile
Write-ManagedModeSmokeResult "managed-mode-codex-invocation-profile-contract"
