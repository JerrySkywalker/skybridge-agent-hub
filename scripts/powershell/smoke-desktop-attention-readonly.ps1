$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
foreach ($required in @("AttentionPanel", "createAttentionModel", "Safe notification status", "External notification sent", "worker_offline", "Refresh", "attention_count", "recommended_next_action")) {
  if (($ui + "`n" + $bridge) -notmatch [regex]::Escape($required)) { throw "Desktop attention surface missing: $required" }
}
foreach ($forbidden in @("start-one -Apply", "start-all -Apply", "resume -Apply", "Worker Loop enabled", "claimTask(")) {
  if (($ui + "`n" + $bridge) -match [regex]::Escape($forbidden)) { throw "Desktop attention surface contains forbidden execution reference: $forbidden" }
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-attention-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
