$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

foreach ($required in @(
  '"campaign-queue"',
  "CampaignQueuePage",
  "Campaign Queue",
  "Queue Control Readiness",
  "Start One disabled",
  "Start Queue disabled",
  "Resume disabled",
  "next_safe_action",
  "createCampaignSafeSummary"
)) {
  if ($web -notmatch [regex]::Escape($required)) {
    throw "Web queue dashboard missing required text or contract use: $required"
  }
}

if ($web -notmatch "fixtureCampaignRunReport" -or $client -notmatch "worker_offline") {
  throw "Web dashboard must consume fixture report data that includes worker_offline."
}

foreach ($forbidden in @(
  "start-one -Apply",
  "start-all -Apply",
  "resume -Apply",
  "skybridge-dev-queue-control.ps1"
)) {
  if ($web -match [regex]::Escape($forbidden)) {
    throw "Web queue dashboard contains forbidden mutation reference: $forbidden"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "web-queue-dashboard-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
