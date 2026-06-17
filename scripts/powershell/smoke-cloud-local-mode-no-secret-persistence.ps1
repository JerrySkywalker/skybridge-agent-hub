$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$client = Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts")
$combined = $client + (Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")) + (Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx"))
foreach ($needle in @("API_MODE_STORAGE_KEY", "API_BASE_STORAGE_KEY", "skybridge.api.mode", "skybridge.api.base")) {
  if ($combined -notlike "*$needle*") { throw "Missing safe storage marker: $needle" }
}
if ($combined -match "localStorage\.setItem\([^,]+,\s*.*(token|secret|authorization|cookie|private)") {
  throw "Secret-like localStorage persistence detected."
}
Write-Host "[smoke-cloud-local-mode-no-secret-persistence] ok"

