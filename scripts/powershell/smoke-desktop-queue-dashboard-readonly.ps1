$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

foreach ($required in @(
  "Read-only Queue Dashboard",
  "Queue Control Readiness",
  "Copy safe summary",
  "Open report",
  "fixtureCampaignRunReport",
  "can_start_one",
  "can_start_queue",
  "can_resume"
)) {
  if ($ui -notmatch [regex]::Escape($required)) {
    throw "Desktop queue dashboard missing required UI text or contract use: $required"
  }
}

if ($ui -notmatch "fixtureCampaignRunReport" -or $client -notmatch "worker_offline") {
  throw "Desktop dashboard must consume fixture report data that includes worker_offline."
}

foreach ($required in @("run_campaign_report", "runner-report", "open_report", "campaign_report", "safe_summary")) {
  if ($bridge -notmatch [regex]::Escape($required)) {
    throw "Desktop bridge missing read-only report support: $required"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-queue-dashboard-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
