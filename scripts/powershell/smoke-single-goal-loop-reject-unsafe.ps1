. "$PSScriptRoot\smoke-productization-common.ps1"

$unsafe = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "unsafe-template", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($unsafe.blockers) -notcontains "unsafe_template_rejected") { throw "Unsafe template was not rejected." }

$codex = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "codex-template", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($codex.blockers) -notcontains "codex_template_rejected") { throw "Codex template was not rejected." }
if (@($codex.blockers) -notcontains "codex_capability_rejected") { throw "Codex capability was not rejected." }

$matlab = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "matlab-template", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($matlab.blockers) -notcontains "matlab_template_rejected") { throw "MATLAB template was not rejected." }
if (@($matlab.blockers) -notcontains "matlab_capability_rejected") { throw "MATLAB capability was not rejected." }

$multi = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "multiple-candidates", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($multi.blockers) -notcontains "multiple_candidate_tasks") { throw "Multiple candidates should be rejected." }

$maxTasks = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-MaxTasks", "2", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($maxTasks.blockers) -notcontains "max_tasks_exceeds_single_goal_limit") { throw "MaxTasks > 1 should be rejected." }

$active = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "active-task", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($active.blockers) -notcontains "active_task_present") { throw "Active task blocker missing." }

$stale = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "stale-lease", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($stale.blockers) -notcontains "stale_lease_present") { throw "Stale lease blocker missing." }

$dependency = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-FixtureScenario", "dependency-blocker", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if (@($dependency.blockers) -notcontains "dependency_not_complete:previous-step") { throw "Dependency blocker missing." }

foreach ($result in @($unsafe, $codex, $matlab, $multi, $maxTasks, $active, $stale, $dependency)) {
  Assert-False $result.task_claimed "task_claimed"
  Assert-False $result.execution_started "execution_started"
  Assert-TokenPrintedFalse $result
}

Complete-Smoke "single-goal-loop-reject-unsafe"
