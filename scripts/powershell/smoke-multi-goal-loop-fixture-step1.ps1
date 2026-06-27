. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/multi-goal-loop-smoke-step1-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-Confirm", "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY", "-OutputDir", $outputDir)
if ($result.schema -ne "skybridge.multi_goal_loop.v1") { throw "Unexpected schema." }
Assert-False $result.preview_only "preview_only"
Assert-True $result.apply_confirmed "apply_confirmed"
if ([string]$result.current_step_id -ne "safe-local-smoke-step-353-001") { throw "Expected step 1 current_step_id." }
if ([string]$result.next_step_id -ne "matlab-golden-step-353-002") { throw "Expected step 2 next_step_id." }
foreach ($name in @("task_created_count", "task_claimed_count", "execution_started_count", "execution_completed_count", "evidence_attached_count", "step_completed_count")) {
  if ([int]$result.$name -ne 1) { throw "Expected $name=1." }
}
Assert-False $result.campaign_completed "campaign_completed"
$step1 = @($result.steps | Where-Object { $_.step_id -eq "safe-local-smoke-step-353-001" } | Select-Object -First 1)
Assert-True $step1[0].completed "step1.completed"
Assert-True $step1[0].evidence_attached "step1.evidence_attached"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "multi-goal-loop-fixture-step1"
