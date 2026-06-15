$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-local-auth-common.ps1"
Invoke-LocalAuthJson "session-create-fixture" | Out-Null
$report = Invoke-LocalAuthJson "session-report"
Assert-False $report.raw_token_persisted "raw_token_persisted"
Assert-False $report.auth_header_persisted "auth_header_persisted"
Assert-False $report.cookie_persisted "cookie_persisted"
Assert-False $report.private_key_persisted "private_key_persisted"
Assert-Truthy $report.token_like_content_rejected "token_like_content_rejected"
Assert-NoTokenPrintedTrueInFile (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\local-auth\session-store\sessions.json")
Invoke-LocalAuthJson "session-expire-fixture" | Out-Null
Invoke-LocalAuthJson "session-revoke-fixture" | Out-Null
Write-Host "[smoke-auth-session-redaction] ok"
