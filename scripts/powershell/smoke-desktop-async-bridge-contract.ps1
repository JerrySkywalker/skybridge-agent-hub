$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")

foreach ($required in @(
  "BridgeOutcome",
  "BridgeResults",
  "bridge_value",
  "campaign_report",
  "worker_status",
  "active",
  "report",
  "warning",
  "operator_readiness",
  "Queue Readiness"
)) {
  if (($bridge + "`n" + $ui) -notmatch [regex]::Escape($required)) {
    throw "Desktop async bridge contract missing: $required"
  }
}

foreach ($forbidden in @("start-one", "start-all", "resume -Apply", "execute-step", "run-until-complete", "run-until-hold", "run-next")) {
  if (($bridge + "`n" + $ui) -match [regex]::Escape($forbidden)) {
    throw "Desktop bridge exposes forbidden execution wording: $forbidden"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-async-bridge-contract"
  token_printed = $false
} | ConvertTo-Json -Compress
