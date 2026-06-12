. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

foreach ($command in @("run-finalizer-preview", "run-finalizer-evidence", "run-finalizer-report", "registry", "safe-summary")) {
  $result = Invoke-ManagedModeRunJson $command
  Assert-ManagedModeRunSafeJson $result
}
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-token-printed-false"
