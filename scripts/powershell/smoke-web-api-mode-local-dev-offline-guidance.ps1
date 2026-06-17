$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$client = Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts")
$web = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
if ($client -notlike "*local_dev*") { throw "Missing local_dev mode." }
if ($client -notlike "*corepack pnpm --filter @skybridge-agent-hub/server dev*") { throw "Missing local dev startup guidance." }
if ($web -notlike "*Connectivity Doctor*") { throw "Web missing Connectivity Doctor panel." }
Write-Host "[smoke-web-api-mode-local-dev-offline-guidance] ok"

