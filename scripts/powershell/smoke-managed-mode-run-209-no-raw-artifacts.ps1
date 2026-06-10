. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$result = Invoke-ManagedModeRunJson "run-apply" -Extra @("-Authorize209B", "-AuthorizationReason", "fixture dry-run authorization", "-SimulateApply")
Assert-ManagedModeRunSafeJson $result
Write-ManagedModeRunSmokeResult "managed-mode-run-209-no-raw-artifacts"
