$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

foreach ($required in @(
  "status.safe_summary ?? (status.campaign_report ? createCampaignSafeSummary(status.campaign_report) : null)",
  "containsSecretLookingText",
  "Safe summary blocked by secret-pattern guard",
  "token_printed",
  "false",
  "read_cached_campaign_report",
  "campaign_report_cached_after_refresh_failure",
  "report_age_seconds"
)) {
  if (($ui + "`n" + $bridge) -notmatch [regex]::Escape($required)) {
    throw "Cached safe summary contract missing: $required"
  }
}

if ($ui -match 'invoke<DesktopStatus>\("get_status".*copySafeSummary') {
  throw "Copy safe summary must not wait for a fresh bridge refresh."
}

if ($ui -match "Authorization: Bearer") {
  throw "Safe summary UI contains forbidden Authorization header text."
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-safe-summary-cached"
  token_printed = $false
} | ConvertTo-Json -Compress
