. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
foreach ($command in @("registry", "archive", "allocate-next", "next-run-preview", "next-run-gate", "safe-summary", "run-preview")) {
  $result = Invoke-ManagedModeRunJson $command
  Assert-ManagedModeRunSafeJson $result
}
Write-ManagedModeRunSmokeResult "managed-mode-run-token-printed-false"
