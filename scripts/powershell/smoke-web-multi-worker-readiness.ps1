$ErrorActionPreference = "Stop"
$ui = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("WorkerRoutingPanel", "Multi-worker Routing", "Selected preview", "Repo max parallel", "Execution controls remain disabled", "task_claimed")) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Web multi-worker readiness surface missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-multi-worker-readiness"; token_printed = $false } | ConvertTo-Json -Compress
