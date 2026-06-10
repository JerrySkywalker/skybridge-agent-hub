. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$diagnostics = Invoke-ManagedModePilotJson "codex-invocation-diagnostics"
$profile = Invoke-ManagedModePilotJson "codex-invocation-profile"
if ($diagnostics.token_printed -ne $false -or $profile.token_printed -ne $false) { throw "Expected token_printed=false." }
Assert-ManagedModeSafeJson $diagnostics
Assert-ManagedModeSafeJson $profile
Write-ManagedModeSmokeResult "managed-mode-codex-invocation-token-printed-false"
