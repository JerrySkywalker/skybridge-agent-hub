$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$report = Invoke-SmokeJson "skybridge-host-consent-preview.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.host_mutation_consent_report.v1") { throw "Host consent report schema mismatch." }
Assert-False $report.consent_gate.host_mutation_allowed "host_mutation_allowed"
Assert-False $report.consent_gate.auth_can_enable_host_mutation "auth_can_enable_host_mutation"
Assert-False $report.host_mutation_performed "host_mutation_performed"
Assert-False $report.installer_real_mutation_allowed "installer_real_mutation_allowed"
Write-Host "[smoke-host-consent-disabled] ok"
