. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$result = Invoke-ManagedModeRunJson "run-apply" -Extra @("-Authorize209B", "-AuthorizationReason", "fixture dry-run authorization", "-SimulateApply")
if ($result.auto_merge_enabled -ne $false) { throw "209 dry-run must not enable auto-merge." }
Write-ManagedModeRunSmokeResult "managed-mode-run-209-no-auto-merge"
