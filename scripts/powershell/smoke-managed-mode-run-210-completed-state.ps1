. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$state = Invoke-ManagedModeRunJson "run-finalizer-preview" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-210",
  "-SequenceNumber", "3",
  "-TargetPath", "docs/managed-mode-v0-operator-checklist.md",
  "-StateDir", ".agent/tmp/managed-mode-run-210"
)
if ($state.can_finalize -ne $false) { throw "Completed run 210 must not finalize again." }
if ($state.final_state -ne "managed_mode_run_210_completed") { throw "Expected completed final state." }
if ($state.blockers -notcontains "managed_mode_run_210_already_completed") { throw "Expected duplicate-run blocker." }
Write-ManagedModeRunSmokeResult "managed-mode-run-210-completed-state"
