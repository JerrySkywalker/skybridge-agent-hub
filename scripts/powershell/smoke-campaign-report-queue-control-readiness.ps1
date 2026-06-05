$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$readiness = $result.report.queue_control_readiness
if (-not $readiness) { throw "Missing queue_control_readiness." }
$required = @("can_start_one", "can_start_queue", "can_pause", "can_stop", "can_emergency_stop", "next_safe_action", "worker_required", "worker_status", "run_budget_required", "reason_required")
foreach ($name in $required) {
  if (-not $readiness.PSObject.Properties[$name]) { throw "queue_control_readiness missing field: $name" }
}
if ($readiness.can_stop -ne $true) { throw "Expected can_stop=true." }
if ($readiness.can_emergency_stop -ne $true) { throw "Expected can_emergency_stop=true." }
if ([string]::IsNullOrWhiteSpace([string]$readiness.next_safe_action)) { throw "Expected next_safe_action." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-queue-control-readiness"; token_printed = $false } | ConvertTo-Json -Compress
