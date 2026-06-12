. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$result = Invoke-ManagedModeRunJson "run-apply" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-211",
  "-SequenceNumber", "4",
  "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
  "-StateDir", ".agent/tmp/managed-mode-run-211-smoke",
  "-Authorize209B",
  "-AuthorizationReason", "smoke preview only",
  "-SimulateApply"
)
if ($result.task_created -ne $true -or $result.task_claimed -ne $true -or $result.codex_execution_count -ne 1) { throw "Expected one simulated workunit/task/claim/execution." }
if ($result.changed_files -notcontains "docs/managed-mode-v0-repeatability-check.md") { throw "Expected run-211 target path." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-apply-one-workunit"
