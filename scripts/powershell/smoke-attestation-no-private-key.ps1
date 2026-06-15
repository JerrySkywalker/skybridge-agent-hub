$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$report = Invoke-SmokeJson "skybridge-attestation-preview.ps1" @("-Command", "report")
Assert-False $report.private_key_committed "private_key_committed"
Assert-False $report.attestation.private_key_generated "private_key_generated"
Assert-False $report.attestation.secret_material_present "secret_material_present"
$root = Resolve-Path "$PSScriptRoot\..\.."
$text = Get-Content -Raw -LiteralPath (Join-Path $root ".agent\tmp\attestation\attestation-preview-report.json")
if (Test-UnsafeText $text) { throw "Unsafe attestation report text." }
Write-Host "[smoke-attestation-no-private-key] ok"
