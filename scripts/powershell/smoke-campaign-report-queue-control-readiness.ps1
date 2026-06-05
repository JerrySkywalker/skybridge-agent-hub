$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" runner-report -GoalPackDir "goals/dev-queue-189-200" -Json | ConvertFrom-Json
$readiness = $result.report.queue_control_readiness
if (-not $readiness) { throw "Missing queue_control_readiness." }
$required = @("can_start_one", "can_start_queue", "can_pause", "can_stop", "can_emergency_stop", "next_safe_action", "worker_required", "worker_status", "run_budget_required", "reason_required")
foreach ($name in $required) {
  if (-not $readiness.PSObject.Properties[$name]) { throw "queue_control_readiness missing field: $name" }
}
if ($readiness.worker_status -ne "unknown") { throw "Expected fixture worker_status=unknown." }
if ($readiness.can_start_one -ne $false) { throw "Expected worker_status unknown to disable can_start_one." }
if ($readiness.can_start_queue -ne $false) { throw "Expected worker_status unknown to disable can_start_queue." }
if (@($readiness.blockers) -notcontains "worker_readiness_unknown" -and @($readiness.required_human_action) -notcontains "verify_worker_online_before_execution") {
  throw "Expected worker readiness blocker or human action."
}
if ([string]$readiness.next_safe_action -match "(?i)(run\s+start-one|start-one\s+-Apply|run\s+start-queue|start-queue\s+now)") {
  throw "next_safe_action must not recommend start-one/start-queue while worker readiness is unknown."
}
if ($readiness.can_stop -ne $true) { throw "Expected can_stop=true." }
if ($readiness.can_emergency_stop -ne $true) { throw "Expected can_emergency_stop=true." }
if ([string]::IsNullOrWhiteSpace([string]$readiness.next_safe_action)) { throw "Expected next_safe_action." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-queue-control-readiness"; token_printed = $false } | ConvertTo-Json -Compress
