$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
foreach ($required in @("close_to_tray_supported: true", "close_to_tray_preview: true", "autostart_enabled: false", "autostart_apply_enabled: false")) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Tray close/autostart state missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-tray-close-to-tray-state"; token_printed = $false } | ConvertTo-Json -Compress
