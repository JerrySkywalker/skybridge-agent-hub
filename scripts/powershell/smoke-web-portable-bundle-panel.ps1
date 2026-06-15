$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-portable-bundle-panel", "Portable Local Bundle", "skybridge.portable_local_bundle.v1", "Install disabled", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web portable bundle marker: $needle" }
}
Write-Host '{"ok":true,"scenario":"web-portable-bundle-panel","token_printed":false}'
