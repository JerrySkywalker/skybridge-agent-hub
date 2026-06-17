$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$desktop = Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx")
foreach ($needle in @("desktop-api-mode-settings", "API Mode Settings", "cloud_operator", "local_dev", "custom", "skybridge.api.mode", "skybridge.api.base", "Start server disabled")) {
  if ($desktop -notlike "*$needle*") { throw "Missing desktop API settings marker: $needle" }
}
Write-Host "[smoke-desktop-api-mode-settings] ok"

