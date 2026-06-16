$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-live-local-server-card", "Live-local Server Card", "Auth Request Card", "Loopback Origin Card", "Route Hardening Card", "Disabled Execution State", "No enabled execute/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop live-local panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in desktop live-local panel." }
Write-Host "[smoke-desktop-live-local-panel] ok"
