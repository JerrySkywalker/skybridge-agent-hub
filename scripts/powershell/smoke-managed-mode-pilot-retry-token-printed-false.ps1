. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  foreach ($command in @("timeout-state", "retry-readiness", "retry-preview", "retry-apply")) {
    $extra = @("-StateDir", $stateDir)
    if ($command -eq "retry-apply") {
      $extra += @("-RetryAuthorization", "-RetryAuthorizationReason", "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists.", "-SimulateRetryApply")
    }
    $result = Invoke-ManagedModePilotJson $command "low-docs" $extra
    Assert-ManagedModeSafeJson $result
  }
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-token-printed-false"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
