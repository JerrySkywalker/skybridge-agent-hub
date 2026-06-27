. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY"
$step2 = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-StepId", "matlab-golden-step-353-002", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-dep2-$([guid]::NewGuid().ToString('N'))")
if (@($step2.blockers) -notcontains "dependency_not_complete:safe-local-smoke-step-353-001") { throw "Step 2 dependency blocker missing." }
$step3 = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-StepId", "codex-report-step-353-003", "-Confirm", $confirm, "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-dep3-$([guid]::NewGuid().ToString('N'))")
if (@($step3.blockers) -notcontains "dependency_not_complete:matlab-golden-step-353-002") { throw "Step 3 dependency blocker missing." }
foreach ($result in @($step2, $step3)) {
  if ([int]$result.task_claimed_count -ne 0 -or [int]$result.execution_completed_count -ne 0) { throw "Dependency blocker allowed execution." }
  Assert-False $result.worker_loop_started "worker_loop_started"
  Assert-TokenPrintedFalse $result
}

Complete-Smoke "multi-goal-loop-dependency-block"
