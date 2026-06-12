. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

foreach ($command in @("registry", "next-run-preview", "next-run-gate", "safe-summary", "run-preview", "run-invocation-profile", "run-finalizer-preview")) {
  $value = Invoke-ManagedModeRunJson $command -Extra @(
    "-ManagedModeRunId", "managed-mode-run-211",
    "-SequenceNumber", "4",
    "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
    "-StateDir", ".agent/tmp/managed-mode-run-211"
  )
  Assert-ManagedModeRunSafeJson $value
}
Write-ManagedModeRunSmokeResult "managed-mode-run-211-token-printed-false"
