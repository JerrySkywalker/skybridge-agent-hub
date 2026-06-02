$ErrorActionPreference = "Stop"
$oldCase = $env:SKYBRIDGE_RUNNER_FIXTURE_CASE
try {
  $env:SKYBRIDGE_RUNNER_FIXTURE_CASE = "advanced-past-failed-state"
  $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command resume -Json | ConvertFrom-Json
  if (-not $json.ok) { throw "Expected resume dry-run ok." }
  if ($json.mode -ne "dry-run") { throw "Expected resume without -Apply to be dry-run." }
  if ($json.mutates -ne $false) { throw "Expected resume dry-run to report mutates=false." }
  if ($json.would_execute_goal_190 -ne $false) { throw "Resume dry-run must not execute Goal 190." }
  if ($json.current_step -notmatch "super-190-campaign-run-report-evidence-ledger") { throw "Expected Goal 190 current step." }
  if ($json.goal_190_unexecuted -ne $true) { throw "Expected Goal 190 to be unexecuted." }
  if ($json.next_safe_action -notmatch "Pre-190 Acceptance Gate") { throw "Expected Pre-190 gate instruction." }
} finally {
  if ($null -eq $oldCase) { Remove-Item Env:\SKYBRIDGE_RUNNER_FIXTURE_CASE -ErrorAction SilentlyContinue }
  else { $env:SKYBRIDGE_RUNNER_FIXTURE_CASE = $oldCase }
}
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-resume-dry-run"; token_printed = $false } | ConvertTo-Json -Compress
