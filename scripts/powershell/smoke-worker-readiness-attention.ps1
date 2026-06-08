$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-worker-routing.ps1" -Command worker-readiness-summary -Scenario all-offline -Json | ConvertFrom-Json
foreach ($event in @("no_ready_worker", "all_workers_offline", "worker_stale", "worker_disabled", "capability_mismatch", "repo_parallelism_blocked", "selected_worker_ready_for_preview_only")) {
  if (@($result.attention_events) -notcontains $event) { throw "Missing attention event $event." }
}
[pscustomobject]@{ ok = $true; scenario = "worker-readiness-attention"; token_printed = $false } | ConvertTo-Json -Compress
