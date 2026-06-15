$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$report = Invoke-SmokeJson "skybridge-sbom-preview.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.sbom_preview_report.v1") { throw "SBOM report schema mismatch." }
Assert-False $report.sbom.network_used "network_used"
Assert-False $report.sbom.package_install_performed "package_install_performed"
Assert-False $report.sbom.upload_performed "upload_performed"
Assert-False $report.sbom.environment_dump_persisted "environment_dump_persisted"
Write-Host "[smoke-sbom-preview] ok"
