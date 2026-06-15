$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($required in @("WebLocalSessionPanel", "Manual Local Session", "doctor summary", "Start preview disabled", "Stop preview disabled", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Missing web local session panel marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-local-session-panel"; token_printed = $false } | ConvertTo-Json -Compress
