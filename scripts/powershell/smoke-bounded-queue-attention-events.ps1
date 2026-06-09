[CmdletBinding()]
param([switch]$Json)
$client = Get-Content (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts") -Raw
foreach ($event in @("bounded_queue_preview_available", "bounded_queue_apply_disabled")) {
  if ($client -notmatch $event) { throw "Missing attention event $event." }
}
if ($client -notmatch 'workunit_preview_plan' -or $client -notmatch 'bounded_queue_readiness') { throw "Campaign report must expose workunit preview attention inputs." }
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-attention-events"; token_printed = $false } | ConvertTo-Json -Compress
