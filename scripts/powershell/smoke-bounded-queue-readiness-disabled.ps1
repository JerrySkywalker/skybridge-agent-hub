[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$readiness = Invoke-WorkunitQueue -Command readiness
if ($readiness.can_start_bounded_queue) { throw "can_start_bounded_queue must be false." }
if ($readiness.start_bounded_queue_apply_available) { throw "apply must be unavailable." }
foreach ($blocker in @("bounded_queue_apply_not_yet_enabled", "requires_future_goal_authorization")) {
  if ($blocker -notin @($readiness.blockers)) { throw "Missing blocker $blocker." }
}
Assert-TokenPrintedFalse $readiness
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-readiness-disabled"; token_printed = $false } | ConvertTo-Json -Compress
