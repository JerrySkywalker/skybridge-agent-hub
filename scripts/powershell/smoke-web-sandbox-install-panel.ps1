$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-sandbox-install-panel", "Install Sandbox", "skybridge.install_sandbox.v1", "Real install disabled", "web-sandbox-upgrade-rollback-panel", "web-sandbox-soak-stability-panel", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web sandbox panel marker: $needle" }
}
[pscustomobject]@{ ok = $true; scenario = "web-sandbox-install-panel"; token_printed = $false } | ConvertTo-Json -Compress
