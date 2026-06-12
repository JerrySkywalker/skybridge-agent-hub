. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$profile = Invoke-ManagedModeRunJson "run-invocation-profile" -Extra @("-ManagedModeRunId", "managed-mode-run-211")
Assert-ManagedModeRunSafeJson $profile
if ($profile.profile_workspace_write_workdir.mutating -ne $true) { throw "Expected selected workspace-write profile metadata." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-no-raw-artifacts"
