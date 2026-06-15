$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-portable-bundle-panel", "Portable Local Bundle", "skybridge.portable_local_bundle.v1", "Install disabled", "token_printed")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop portable bundle marker: $needle" }
}
Write-Host '{"ok":true,"scenario":"desktop-portable-bundle-panel","token_printed":false}'
