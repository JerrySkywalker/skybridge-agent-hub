$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($required in @("DesktopLocalSessionPanel", "Manual Local Session", "doctor summary", "Start preview", "Stop preview", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Missing desktop local session panel marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-local-session-panel"; token_printed = $false } | ConvertTo-Json -Compress
