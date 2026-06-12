$ErrorActionPreference = "Stop"
$web = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("WebResidentWorkerSummaryPanel", "web-resident-worker-summary-panel", "Desktop Resident Worker", "execution_enabled=", "queue_apply_enabled=", "Workunit C absent", "token_printed=false")) {
  if ($web -notmatch [regex]::Escape($required)) { throw "Web resident worker summary missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-resident-worker-summary"; token_printed = $false } | ConvertTo-Json -Compress
