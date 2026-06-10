. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists."
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $before = (git status --short | Out-String).Trim()
  Invoke-ManagedModePilotJson "retry-apply" "low-docs" @("-StateDir", $stateDir, "-RetryAuthorization", "-RetryAuthorizationReason", $reason, "-SimulateRetryApply") | Out-Null
  $after = (git status --short | Out-String).Trim()
  if ($before -ne $after) { throw "Retry simulation changed worktree." }
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-clean-worktree"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
