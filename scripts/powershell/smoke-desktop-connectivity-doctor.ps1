$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$desktop = Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx")
foreach ($needle in @("desktop-connectivity-doctor-card", "Connectivity Doctor", "REST health status", "SSE stream status", "Manual refresh", "Backend auto-start", "Host mutation")) {
  if ($desktop -notlike "*$needle*") { throw "Missing desktop Connectivity Doctor marker: $needle" }
}
Write-Host "[smoke-desktop-connectivity-doctor] ok"

