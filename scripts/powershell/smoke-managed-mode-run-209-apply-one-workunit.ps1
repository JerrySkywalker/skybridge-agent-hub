. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$result = Invoke-ManagedModeRunJson "run-apply" -Extra @("-Authorize209B", "-AuthorizationReason", "fixture dry-run authorization", "-SimulateApply")
if ($result.workunit_id -ne "managed-mode-run-209-workunit-001" -or $result.codex_execution_count -ne 1) { throw "209 dry-run must model exactly one workunit and one Codex execution." }
if ($result.task_created -ne $true -or $result.task_claimed -ne $true) { throw "209 dry-run must model one task and one claim." }
Write-ManagedModeRunSmokeResult "managed-mode-run-209-apply-one-workunit"
