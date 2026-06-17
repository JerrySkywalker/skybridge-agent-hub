$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$web = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
foreach ($needle in @("Promise.allSettled", "settledValue", "settledError", "summary", "prs", "hermes", "tasksSummary")) {
  if ($web -notlike "*$needle*") { throw "Missing partial degradation marker: $needle" }
}
if ($web -like "*setSummary(nextSummary)*") { throw "Overview still appears to require all modules." }
Write-Host "[smoke-web-overview-partial-degradation] ok"

