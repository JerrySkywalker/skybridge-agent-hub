[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$desktopBridge = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src-tauri\src\lib.rs")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")

foreach ($needle in @(
  "Bootstrap Alpha Worker Setup",
  "Tool capability matrix",
  "Install preview",
  "Install apply unavailable in Desktop",
  "Repair preview",
  "Repair apply unavailable in Desktop",
  "Heartbeat pairing preview",
  "Heartbeat apply unavailable in Desktop",
  "Doctor read-only",
  "claim_enabled=false",
  "execute_enabled=false",
  "worker_loop_started=false; token_printed=false",
  "Worker loop unavailable",
  "Codex execution disabled",
  "MATLAB execution disabled",
  "LocalWorkerServiceStatus",
  "fixtureLocalWorkerServiceStatus"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) { throw "Desktop worker service manager missing text: $needle" }
}

foreach ($needle in @(
  "skybridge.local_worker_service_status.v1",
  "install_apply_available",
  "heartbeat_apply_available",
  "cloud_worker_registered",
  "claim_enabled: false",
  "execute_enabled: false",
  "template_runner_enabled: false",
  "worker_loop_started: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) { throw "Client fixture missing worker service manager contract text: $needle" }
}

foreach ($needle in @(
  "local_worker_service_status",
  "run_local_worker_service_status",
  "skybridge-worker-service-status.ps1",
  "fixture_local_worker_service_status"
)) {
  if ($desktopBridge -notmatch [regex]::Escape($needle)) { throw "Desktop bridge missing worker service status wiring: $needle" }
}

if ($desktopSource -match [regex]::Escape("Start Worker Loop disabled")) {
  throw "Desktop added a Start Worker Loop button label."
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-worker-service-manager"
  panel_contract = "skybridge.local_worker_service_status.v1"
  claim_enabled = $false
  execute_enabled = $false
  worker_loop_started = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
