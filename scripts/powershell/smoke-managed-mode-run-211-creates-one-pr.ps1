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
if ($result.pr_created -ne $true -or $result.pr_count -ne 1) { throw "Expected one simulated PR." }
if ($result.auto_merge_enabled -ne $false) { throw "Auto-merge must remain disabled." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-creates-one-pr"
