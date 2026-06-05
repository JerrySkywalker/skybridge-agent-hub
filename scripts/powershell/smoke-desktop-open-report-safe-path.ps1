$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")

foreach ($required in @(
  "campaign_reports_dir",
  "report_file_path",
  ".agent",
  "campaign-reports",
  "report path is outside the safe campaign report artifact directory",
  "campaign report artifact is missing; use Refresh to generate it in the background",
  "window.setTimeout",
  "void refresh()"
)) {
  if (($bridge + "`n" + $ui) -notmatch [regex]::Escape($required)) {
    throw "Open report safe-path behavior missing: $required"
  }
}

if ($bridge -match "collect_status\(&app\)\?\s*;\s*let report_file") {
  throw "Open report must not perform a blocking full refresh before opening the artifact."
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-open-report-safe-path"
  token_printed = $false
} | ConvertTo-Json -Compress
