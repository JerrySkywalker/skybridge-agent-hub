. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$profile = Invoke-ManagedModePilotJson "codex-invocation-profile"
if ($profile.profile_disabled_unknown.command_class -ne "codex_profile_disabled_unknown") { throw "Unknown profile must fail closed." }
if ($profile.profile_disabled_unknown.selected_for_managed_mode -ne $false) { throw "Unknown profile must not be selected." }
if (@($profile.profile_disabled_unknown.arguments).Count -ne 0) { throw "Unknown profile must not define executable arguments." }
Assert-ManagedModeSafeJson $profile
Write-ManagedModeSmokeResult "managed-mode-codex-invocation-rejects-unknown-profile"
