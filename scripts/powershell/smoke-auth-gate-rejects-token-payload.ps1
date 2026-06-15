$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-local-auth-common.ps1"
$payload = "scanner_test_fixture_token_like_payload=redacted; token_printed=true"
$result = Invoke-LocalAuthJson "validate-request" @("-Payload", $payload)
if ($result.accepted -ne $false) { throw "Unsafe auth payload was accepted." }
if (@($result.reasons).Count -lt 1) { throw "No rejection reason returned." }
Assert-LocalAuthDisabled $result
Write-Host "[smoke-auth-gate-rejects-token-payload] ok"
