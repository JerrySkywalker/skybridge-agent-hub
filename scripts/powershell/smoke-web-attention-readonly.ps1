$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
foreach ($required in @("AttentionBanner", "AttentionFeed", "NotificationRoutingPanel", "createAttentionModel", "worker_offline", "Notification Routing", "no external send")) {
  if ($web -notmatch [regex]::Escape($required)) { throw "Web attention surface missing: $required" }
}
foreach ($forbidden in @("start-one -Apply", "start-all -Apply", "resume -Apply", "Worker Loop enabled")) {
  if ($web -match [regex]::Escape($forbidden)) { throw "Web attention surface contains forbidden execution reference: $forbidden" }
}

[pscustomobject]@{
  ok = $true
  scenario = "web-attention-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
