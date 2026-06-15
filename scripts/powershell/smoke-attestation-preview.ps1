$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$report = Invoke-SmokeJson "skybridge-attestation-preview.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.attestation_preview_report.v1") { throw "Attestation report schema mismatch." }
Assert-Truthy $report.preview_only "preview_only"
Assert-Truthy $report.fixture_signature "fixture_signature"
Assert-False $report.signing_key_present "signing_key_present"
Write-Host "[smoke-attestation-preview] ok"
