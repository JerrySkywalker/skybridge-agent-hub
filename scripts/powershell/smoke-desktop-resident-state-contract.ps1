$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
foreach ($required in @(
  "skybridge.desktop_resident_state.v1",
  "tray_available",
  "window_visible",
  "close_to_tray_supported",
  "autostart_supported",
  "autostart_enabled",
  "resident_mode",
  "token_printed: false"
)) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Desktop resident contract missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-resident-state-contract"; token_printed = $false } | ConvertTo-Json -Compress
