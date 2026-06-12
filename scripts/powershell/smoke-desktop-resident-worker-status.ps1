$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @(
  "skybridge.desktop_resident_worker.v1",
  "skybridge.desktop_tray_state.v1",
  "skybridge.desktop_worker_control_state.v1",
  "skybridge.desktop_worker_safety_banner.v1",
  "resident_enabled: false",
  "execution_enabled: false",
  "queue_apply_enabled: false",
  "no_next_execution_authorized: true",
  "Desktop Resident Worker",
  "Open Evidence Folder",
  "Open Logs Folder"
)) {
  if (($client + $desktop) -notmatch [regex]::Escape($required)) { throw "Resident worker status missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-resident-worker-status"; token_printed = $false } | ConvertTo-Json -Compress
