. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$preview = Invoke-ManagedModeRunJson "run-preview" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-211",
  "-SequenceNumber", "4",
  "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
  "-StateDir", ".agent/tmp/managed-mode-run-211"
)
if ($preview.gate.general_bounded_queue_apply_enabled -ne $false -or $preview.gate.run_apply_enabled -ne $false) { throw "Apply controls must be disabled by default." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-no-auto-merge"
