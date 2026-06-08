$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-attention-fixture.ps1" -Command list -Json | ConvertFrom-Json
$events = @($result.attention_events)
if (-not $result.ok) { throw "Attention fixture did not return ok=true." }
if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }
if (-not (@($events | Where-Object { $_.event_type -eq "worker_offline" -and $_.attention_level -in @("action_required", "blocker") }).Count)) {
  throw "worker_offline attention event missing."
}
if (-not (@($events | Where-Object { $_.event_type -eq "human_approval_required" }).Count)) {
  throw "human_approval_required attention event missing."
}

[pscustomobject]@{
  ok = $true
  scenario = "attention-derivation-worker-offline"
  attention_count = $events.Count
  worker_status = "offline"
  token_printed = $false
} | ConvertTo-Json -Compress
