[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$web = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($needle in @("manual_task_routes_available", "deployment_parity_status", "Cloud server online but outdated; deploy server", "Server version", "Image tag", "Route set version")) {
  if ($web -notmatch [regex]::Escape($needle)) { throw "Web outdated warning contract missing: $needle" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "web-cloud-outdated-warning"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
