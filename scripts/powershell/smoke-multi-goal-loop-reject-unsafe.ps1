. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY"
$unsafe = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-FixtureScenario", "unsafe-template", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-unsafe-$([guid]::NewGuid().ToString('N'))")
if (@($unsafe.blockers) -notcontains "unsafe_template_rejected") { throw "Unsafe template was not rejected." }
$unknown = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-FixtureScenario", "unknown-template", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-unknown-$([guid]::NewGuid().ToString('N'))")
if (@($unknown.blockers) -notcontains "unknown_template_rejected") { throw "Unknown template was not rejected." }
$active = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-FixtureScenario", "active-task", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-active-$([guid]::NewGuid().ToString('N'))")
if (@($active.blockers) -notcontains "active_task_present") { throw "Active task blocker missing." }
$stale = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-FixtureScenario", "stale-lease", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-stale-$([guid]::NewGuid().ToString('N'))")
if (@($stale.blockers) -notcontains "stale_lease_present") { throw "Stale lease blocker missing." }
$multiple = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-FixtureScenario", "multiple-candidates", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-multiple-$([guid]::NewGuid().ToString('N'))")
if (@($multiple.blockers) -notcontains "multiple_candidate_tasks") { throw "Multiple candidate blocker missing." }
$maxSteps = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-MaxSteps", "2", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-max-$([guid]::NewGuid().ToString('N'))")
if (@($maxSteps.blockers) -notcontains "max_steps_must_be_1") { throw "MaxSteps > 1 was not rejected." }

foreach ($result in @($unsafe, $unknown, $active, $stale, $multiple, $maxSteps)) {
  if ([int]$result.task_claimed_count -ne 0 -or [int]$result.execution_completed_count -ne 0) { throw "Reject path allowed execution." }
  Assert-False $result.codex_run_called "codex_run_called"
  Assert-False $result.matlab_run_called "matlab_run_called"
  Assert-False $result.worker_loop_started "worker_loop_started"
  Assert-TokenPrintedFalse $result
}

Complete-Smoke "multi-goal-loop-reject-unsafe"
