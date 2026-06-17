$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$client = Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts")
foreach ($needle in @(
  "skybridge.connectivity_doctor.v1",
  "api_mode",
  "api_base",
  "rest_health_status",
  "sse_stream_status",
  "server_online",
  "stream_degraded",
  "last_health_time",
  "last_error_summary",
  "recommended_action",
  "token_printed: false"
)) {
  if ($client -notlike "*$needle*") { throw "Missing connectivity doctor model marker: $needle" }
}
Write-Host "[smoke-connectivity-doctor-model] ok"

