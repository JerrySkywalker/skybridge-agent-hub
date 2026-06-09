$text = Get-Content (Join-Path $PSScriptRoot "../../apps/desktop/src/main.tsx") -Raw
foreach ($required in @("WorkerPoolPreviewPanel", "Worker Pool Preview", "Scheduling apply disabled", "Create lease disabled", "token_printed")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Desktop worker pool preview panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-worker-pool-preview-panel"; token_printed = $false } | ConvertTo-Json -Compress
