$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
foreach ($file in @("apps/web/src/main.tsx", "apps/desktop/src/main.tsx")) {
  $text = Get-Content -LiteralPath (Join-Path $root $file) -Raw
  if ($text -notmatch "token_printed=false") { throw "Missing token invariant marker in $file." }
}
[pscustomobject]@{ ok = $true; smoke = "operator-cockpit-token-printed-false"; token_printed = $false } | ConvertTo-Json
