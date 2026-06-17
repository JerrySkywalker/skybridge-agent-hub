$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$client = Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts")
$docs = Get-Content -Raw -LiteralPath (Join-Path $root "docs\dev\CLOUD_FIRST_OPERATOR_MODE.md")
if ($client -notlike "*cloud_operator*") { throw "Missing cloud_operator mode." }
if ($client -notlike "*Cloud API unreachable. Check API base and network access.*") { throw "Missing cloud API guidance." }
if ($docs -like "*corepack pnpm --filter @skybridge-agent-hub/server dev*") { throw "Cloud docs mention local server startup." }
Write-Host "[smoke-web-api-mode-cloud-no-local-server-guidance] ok"

