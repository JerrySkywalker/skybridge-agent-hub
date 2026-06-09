$text = Get-Content (Join-Path $PSScriptRoot "../../apps/web/src/main.tsx") -Raw
foreach ($required in @("WorkerSchedulingPreviewPanel", "Scheduling Preview", "Worker claim disabled", "Lease creation disabled", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web worker scheduling preview panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-worker-scheduling-preview-panel"; token_printed = $false } | ConvertTo-Json -Compress
