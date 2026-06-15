$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($required in @("WebLauncherSupervisorPanel", "Launcher / Supervisor", "Session supervisor panel", "WebOperatorWalkthroughPanel", "Next safe action panel", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Missing web launcher marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-launcher-supervisor-panel"; token_printed = $false } | ConvertTo-Json -Compress
