$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$text = Get-Content -Raw -LiteralPath (Join-Path $repo "apps/desktop/src/main.tsx")
foreach ($required in @("BOINC v1 alpha completed", "Alpha completed", "Workunit C absent", "Next safe action", "token_printed=false")) {
  if ($text -notlike "*$required*") { throw "missing desktop completed alpha marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-boinc-v1-alpha-completed-panel"; token_printed = $false } | ConvertTo-Json -Compress
