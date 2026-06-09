$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
if ($client -notmatch "close_to_tray_supported:\s*false") { throw "Close-to-tray must remain disabled metadata until safely implemented." }
if ($desktop -notmatch "disabled pending safe window-close handler") { throw "Desktop UI must explain close-to-tray disabled state." }
[pscustomobject]@{ ok = $true; scenario = "desktop-close-to-tray-safe"; close_to_tray_supported = $false; token_printed = $false } | ConvertTo-Json -Compress
