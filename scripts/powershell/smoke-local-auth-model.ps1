$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-local-auth-common.ps1"
$report = Invoke-LocalAuthJson "report"
if ($report.schema -ne "skybridge.local_auth_report.v1") { throw "Local auth report schema mismatch." }
Assert-False $report.model.remote_origins_allowed "remote_origins_allowed"
Assert-False $report.model.raw_token_persisted "raw_token_persisted"
Assert-False $report.model.auth_header_persisted "auth_header_persisted"
Assert-Truthy $report.model.token_hash_present "token_hash_present"
Assert-LocalAuthDisabled $report.model
Assert-NoTokenPrintedTrueInFile (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\local-auth\local-auth-report.json")
Write-Host "[smoke-local-auth-model] ok"
