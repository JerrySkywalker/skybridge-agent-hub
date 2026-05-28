[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"

$runbook = Get-Content -Raw -LiteralPath .\docs\operations\HERMES_DIRECT_API.md
$config = Get-Content -Raw -LiteralPath .\docs\operations\openresty-hermes-api.example.conf

foreach ($expected in @(
  "hermes-api.jerryskywalker.space",
  "127.0.0.1:8642",
  "Authorization: Bearer",
  "skybridge-hermes-health.ps1",
  "skybridge-hermes-preview.ps1",
  "http://127.0.0.1:18642"
)) {
  if ($runbook -notlike "*$expected*") { throw "Runbook missing expected text: $expected" }
}

foreach ($expected in @(
  "server 127.0.0.1:8642",
  "proxy_set_header Authorization `$http_authorization",
  "proxy_read_timeout 300s",
  "proxy_buffering off",
  "proxy_request_buffering off",
  "X-Accel-Buffering no"
)) {
  if ($config -notlike "*$expected*") { throw "OpenResty example missing expected text: $expected" }
}

$summary = [pscustomobject]@{
  ok = $true
  runbook = "docs/operations/HERMES_DIRECT_API.md"
  config = "docs/operations/openresty-hermes-api.example.conf"
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
