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
if ($result.final_state -ne "held_waiting_human_pr_review" -or $result.stop_on_pr_created -ne $true) { throw "Expected stop on PR created." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-stops-on-pr-created"
