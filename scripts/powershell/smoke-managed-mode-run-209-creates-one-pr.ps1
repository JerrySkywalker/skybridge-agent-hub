. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$result = Invoke-ManagedModeRunJson "run-apply" -Extra @("-Authorize209B", "-AuthorizationReason", "fixture dry-run authorization", "-SimulateApply")
if ($result.pr_created -ne $true -or $result.pr_count -ne 1) { throw "209 dry-run must model exactly one PR." }
Write-ManagedModeRunSmokeResult "managed-mode-run-209-creates-one-pr"
