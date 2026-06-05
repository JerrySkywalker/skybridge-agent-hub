$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")

foreach ($required in @(
  "CampaignRunReport",
  "CampaignQueueControlReadiness",
  "CampaignEvidenceEntry",
  "summarizeCampaignEvidence",
  "createCampaignSafeSummary",
  "fixtureCampaignRunReport",
  "skybridge.campaign_run_report.v1",
  "token_printed: false"
)) {
  if ($client -notmatch [regex]::Escape($required)) {
    throw "Shared campaign report contract missing: $required"
  }
}

foreach ($required in @(
  "campaign_summary",
  "current_step_summary",
  "previous_step_summary",
  "step_ledger",
  "evidence_ledger",
  "queue_control_readiness",
  "worker_status",
  "next_safe_action"
)) {
  if ($client -notmatch [regex]::Escape($required)) {
    throw "Campaign report contract missing field: $required"
  }
}

if ($web -notmatch "fixtureCampaignRunReport" -or $desktop -notmatch "fixtureCampaignRunReport") {
  throw "Web and Desktop must both consume the shared fixture report."
}

[pscustomobject]@{
  ok = $true
  scenario = "campaign-report-contract-consumer"
  token_printed = $false
} | ConvertTo-Json -Compress
