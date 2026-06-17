$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "report")
$text = $report | ConvertTo-Json -Depth 100
foreach ($forbidden in @("Authorization", "Bearer ", "api_key", "HERMES_DEEPSEEK_API_KEY=", "raw_request_body", "raw_response_body")) {
  if ($text -like "*$forbidden*") { throw "Provider report exposed forbidden config text: $forbidden" }
}
if ($text -match '(?i)(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}') { throw "Provider report exposed key-like text." }
Assert-False $report.raw_request_persisted "raw_request_persisted"
Assert-False $report.raw_response_persisted "raw_response_persisted"
Assert-False $report.output_executed "output_executed"
Write-Host "[smoke-manual-task-hermes-config-redaction] ok"
