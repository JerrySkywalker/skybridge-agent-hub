$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @(
  "packages\client\src\index.ts",
  "apps\web\src\main.tsx",
  "apps\desktop\src\main.tsx",
  "docs\dev\CONNECTIVITY_DOCTOR.md"
)
foreach ($relative in $paths) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $relative)
  if ($text -notlike "*token_printed*false*") { throw "Missing token_printed=false marker in $relative" }
  if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token_printed true marker in $relative" }
}
Write-Host "[smoke-connectivity-doctor-token-printed-false] ok"

