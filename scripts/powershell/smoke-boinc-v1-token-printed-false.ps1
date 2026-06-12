. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
@("status", "two-workunit-preview", "queue-preview", "apply-gate", "safe-summary", "readiness", "report", "drain-policy", "action-matrix") | ForEach-Object {
  $result = Invoke-BoincV1PreviewJson -Command $_
  Assert-False ([bool]$result.token_printed) "Expected top-level token_printed=false for $_."
}
Write-SmokeResult "boinc-v1-token-printed-false"
