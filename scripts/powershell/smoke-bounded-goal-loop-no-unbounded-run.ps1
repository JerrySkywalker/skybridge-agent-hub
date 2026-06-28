. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-bounded-goal-loop.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
if ($source -match 'while\s*\(\s*\$true\s*\)|for\s*\(\s*;\s*;\s*\)|Start-Job|Register-ScheduledJob|Start-Service|worker_loop_started\s*=\s*\$true|project_control_unpaused\s*=\s*\$true') {
  throw "Potential unbounded or service-start pattern detected."
}
$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "ready-step",
  "-Confirm", $confirm
)
if ([int]$result.action_count -ne 1) { throw "Expected exactly one bounded action." }
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-no-unbounded-run"
