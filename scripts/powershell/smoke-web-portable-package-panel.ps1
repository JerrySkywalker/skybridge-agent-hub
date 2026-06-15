$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-portable-package-panel", "Portable Package Candidate", "skybridge.portable_package.v1", "Install disabled", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web portable package marker: $needle" }
}
Write-Host '{"ok":true,"scenario":"web-portable-package-panel","token_printed":false}'
