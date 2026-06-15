$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-local-auth-status-panel", "Loopback / Origin Policy", "Session State", "Auth Rejection Summary", "Execution disabled by local auth", "No real login", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web auth panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token_printed=true found in web auth panel." }
Write-Host "[smoke-web-auth-panel] ok"
