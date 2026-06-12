$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$text = Get-Content -Raw -LiteralPath (Join-Path $repo "apps/desktop/src/main.tsx")
foreach ($required in @("Workunit B review only", "Workunit C absent", "No next execution authorized", "token_printed=false")) {
  if ($text -notlike "*$required*") { throw "missing desktop Workunit B marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-boinc-v1-alpha-workunit-b-panel"; token_printed = $false } | ConvertTo-Json -Compress
