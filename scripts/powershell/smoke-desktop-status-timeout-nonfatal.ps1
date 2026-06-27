$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")

foreach ($required in @(
  'worker: worker.unwrap_or_else',
  'worker status bridge did not return before desktop refresh deadline',
  'report: report.unwrap_or_else',
  'campaign report bridge did not return before desktop refresh deadline',
  'let warning = format!("{name}: {}"',
  'warnings.push(warning.clone())',
  'ok: !token_printed && !campaign_report.is_null()',
  "Status refreshed with cached report",
  'Bridge Warnings'
)) {
  if (($bridge + "`n" + $ui) -notmatch [regex]::Escape($required)) {
    throw "Desktop status timeout nonfatal behavior missing: $required"
  }
}

if ($bridge -match "errors\.extend") {
  throw "Bridge warning outcomes must not be promoted to fatal desktop errors."
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-status-timeout-nonfatal"
  token_printed = $false
} | ConvertTo-Json -Compress
