$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$request = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "auth-request", "-Route", "/metadata", "-Origin", "http://127.0.0.1:5173")
if ($request.schema -ne "skybridge.live_local_auth_request.v1") { throw "Live-local auth request schema mismatch." }
if ($request.accepted -ne $true) { throw "Live-local auth request was not accepted." }
if ($request.status -ne "safe_metadata_read") { throw "Live-local auth request status mismatch." }
Assert-False $request.raw_token_persisted "raw_token_persisted"
Assert-False $request.auth_header_persisted "auth_header_persisted"
Assert-False $request.cookie_persisted "cookie_persisted"
Assert-False $request.private_key_persisted "private_key_persisted"
Assert-False $request.execution_enabled "execution_enabled"
Assert-False $request.worker_execution_started "worker_execution_started"
Assert-False $request.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-live-local-auth-request] ok"
