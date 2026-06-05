$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

foreach ($required in @(
  "async fn get_status",
  "spawn_blocking",
  "collect_bridge_results",
  "mpsc::channel",
  "recv_timeout",
  "BRIDGE_RESULT_TIMEOUT_SECONDS",
  "report_cached",
  "bridge_outcomes",
  "refreshGeneration",
  "Older refresh result ignored",
  "Refreshing in background; cached report remains visible"
)) {
  if (($ui + "`n" + $bridge) -notmatch [regex]::Escape($required)) {
    throw "Desktop nonblocking refresh contract missing: $required"
  }
}

if ($bridge -match "let _ = collect_status\(app\);") {
  throw "Tray refresh must not synchronously collect status on the UI event path."
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-refresh-nonblocking"
  token_printed = $false
} | ConvertTo-Json -Compress
