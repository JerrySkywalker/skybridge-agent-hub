$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$path = Join-Path $repo "apps/desktop/src/main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($required in @("CoreEngineStatusPanel", "Core Engine", "completed run registry", "token_printed=false")) {
  if ($text -notlike "*$required*") { throw "missing desktop core engine panel marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-core-engine-status-panel"; token_printed = $false } | ConvertTo-Json -Compress
