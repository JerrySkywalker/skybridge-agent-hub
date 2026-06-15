$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($required in @("DesktopLauncherSupervisorPanel", "Launcher / Supervisor", "Session supervisor card", "Walkthrough/demo card", "Doctor action guide card", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Missing desktop launcher marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-launcher-supervisor-panel"; token_printed = $false } | ConvertTo-Json -Compress
