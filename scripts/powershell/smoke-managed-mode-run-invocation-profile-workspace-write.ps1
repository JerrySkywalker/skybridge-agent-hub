. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$profile = Invoke-ManagedModeRunJson "run-invocation-profile"
if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile." }
if ($profile.profile_workspace_write_workdir.arguments -notcontains "--sandbox") { throw "Expected sandbox argument." }
if ($profile.profile_workspace_write_workdir.arguments -notcontains "workspace-write") { throw "Expected workspace-write argument." }
Assert-ManagedModeRunSafeJson $profile
Write-ManagedModeRunSmokeResult "managed-mode-run-invocation-profile-workspace-write"
