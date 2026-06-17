$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$client = Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts")
$web = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
foreach ($needle in @("rest_health_status", "sse_stream_status", "server_online", "stream_degraded", "REST health status", "SSE stream status")) {
  if (($client + $web) -notlike "*$needle*") { throw "Missing REST/SSE split marker: $needle" }
}
if ($client -notlike "*Server online; SSE stream degraded*") { throw "Missing degraded stream guidance." }
Write-Host "[smoke-web-rest-health-not-sse-offline] ok"

