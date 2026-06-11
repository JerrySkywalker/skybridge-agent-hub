. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

foreach ($command in @("run-finalizer-preview", "run-finalizer-evidence", "run-finalizer-report", "run-finalizer-apply")) {
  $result = Invoke-ManagedModeRunJson $command
  Assert-ManagedModeRunSafeJson $result
}
Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-token-printed-false"
