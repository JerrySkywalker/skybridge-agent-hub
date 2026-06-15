$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-local-auth-card", "Session State Card", "Loopback Origin Card", "Disabled Execution Card", "No raw token display", "Worker execute disabled", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop auth panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token_printed=true found in desktop auth panel." }
Write-Host "[smoke-desktop-auth-panel] ok"
