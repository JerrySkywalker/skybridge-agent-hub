$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$web = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx")
foreach ($text in @($web, $desktop)) {
  if ($text -notlike "*Manual Task provider panel uses selected API base for server-mediated Hermes status*") {
    throw "Manual Task provider panel is not tied to selected API base."
  }
}
Write-Host "[smoke-manual-task-provider-panel-selected-api-base] ok"

