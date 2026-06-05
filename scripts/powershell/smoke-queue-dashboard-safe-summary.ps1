$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

foreach ($required in @(
  "skybridge.campaign_safe_summary.v1",
  "campaign_id",
  "current_step",
  "queue_readiness",
  "blockers",
  "warnings",
  "worker_status",
  "token_printed: false",
  "containsSecretLookingText"
)) {
  if (($client + "`n" + $desktop + "`n" + $bridge) -notmatch [regex]::Escape($required)) {
    throw "Safe summary missing required guard or field: $required"
  }
}

$secretPattern = "(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)"
foreach ($text in @($client, $desktop, $bridge)) {
  if ($text -match $secretPattern) {
    throw "Safe summary code contains secret-looking text."
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "queue-dashboard-safe-summary"
  token_printed = $false
} | ConvertTo-Json -Compress
