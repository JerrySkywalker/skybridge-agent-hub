$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-live-local-server-status-panel", "Live-local Server Status", "Auth Request Status", "Loopback Origin Status", "Route Hardening Status", "Disabled Execution State", "No enabled execute/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web live-local panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in web live-local panel." }
Write-Host "[smoke-web-live-local-panel] ok"
