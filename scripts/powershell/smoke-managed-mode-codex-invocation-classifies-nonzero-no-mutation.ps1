. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotRetryResult -StateDir $stateDir -TimedOut:$false
  $summary = Invoke-ManagedModePilotJson "codex-invocation-safe-summary" "low-docs" @("-StateDir", $stateDir)
  if ($summary.previous_retry_classification.classification -ne "invocation_failed_no_mutation") { throw "Expected invocation_failed_no_mutation." }
  if ($summary.previous_retry_classification.timed_out -ne $false) { throw "Nonzero no-mutation retry must not be classified as timeout." }
  Assert-ManagedModeSafeJson $summary
  Write-ManagedModeSmokeResult "managed-mode-codex-invocation-classifies-nonzero-no-mutation"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
