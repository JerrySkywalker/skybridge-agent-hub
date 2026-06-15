$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-portable-package-panel", "Portable Package Candidate", "skybridge.portable_package.v1", "Install disabled", "token_printed")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop portable package marker: $needle" }
}
Write-Host '{"ok":true,"scenario":"desktop-portable-package-panel","token_printed":false}'
