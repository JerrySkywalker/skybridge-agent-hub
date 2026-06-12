$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$text = Get-Content -Raw -LiteralPath (Join-Path $repo "apps/desktop/src/main.tsx")
foreach ($required in @("BoincV1AlphaPanel", "BOINC v1 Alpha", "Workunit C absent", "token_printed=false")) {
  if ($text -notlike "*$required*") { throw "missing desktop alpha marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-boinc-v1-alpha-panel"; token_printed = $false } | ConvertTo-Json -Compress
