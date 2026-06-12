. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$state = Invoke-ManagedModeRunJson "run-finalizer-apply" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-211",
  "-SequenceNumber", "4",
  "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
  "-StateDir", ".agent/tmp/managed-mode-run-211"
)
if ($state.ok -ne $false) { throw "Duplicate finalizer apply must be refused." }
if ($state.blockers -notcontains "managed_mode_run_211_already_completed") { throw "Expected already-completed blocker." }
Assert-ManagedModeRunSafeJson $state
Write-ManagedModeRunSmokeResult "managed-mode-run-211-refuses-rerun"
