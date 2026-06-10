. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$reason = "Renewed operator authorization after prior launcher failure before execution; launcher repair merged; no prior task PR or executor evidence exists."
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-RequireRenewedAuthorization", "-RenewedAuthorization", "-RenewedAuthorizationReason", $reason, "-SimulateApply")
if ($result.token_printed -ne $false -or $result.renewed_authorization -ne $true) { throw "Renewed apply token_printed=false contract failed." }
Assert-ManagedModeSafeJson $result
Write-ManagedModeSmokeResult "managed-mode-pilot-renewed-apply-token-printed-false"
