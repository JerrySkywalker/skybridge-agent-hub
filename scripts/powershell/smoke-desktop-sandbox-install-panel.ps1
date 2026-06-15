$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-sandbox-install-panel", "Install Sandbox", "skybridge.install_sandbox.v1", "Real install disabled", "desktop-sandbox-upgrade-rollback-panel", "desktop-sandbox-soak-stability-panel", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop sandbox panel marker: $needle" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-sandbox-install-panel"; token_printed = $false } | ConvertTo-Json -Compress
