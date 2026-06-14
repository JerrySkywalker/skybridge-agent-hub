$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$text = Get-Content -LiteralPath (Join-Path $root "apps/desktop/src/main.tsx") -Raw
foreach ($needle in @("Operator Cockpit", "Bootstrap Complete", "Completed Runs", "Trusted-docs Scoped Merge", "no_next_execution_authorized=true", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing desktop cockpit text: $needle" }
}
[pscustomobject]@{ ok = $true; smoke = "desktop-operator-cockpit"; token_printed = $false } | ConvertTo-Json
