. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/multi-goal-loop-smoke-all-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY"
$step1 = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-Confirm", $confirm, "-OutputDir", $outputDir)
$step2 = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-Confirm", $confirm, "-OutputDir", $outputDir)
$step3 = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-Confirm", $confirm, "-OutputDir", $outputDir)

if ([string]$step1.current_step_id -ne "safe-local-smoke-step-353-001") { throw "Step 1 did not run first." }
if ([string]$step2.current_step_id -ne "matlab-golden-step-353-002") { throw "Step 2 did not run second." }
if ([string]$step3.current_step_id -ne "codex-report-step-353-003") { throw "Step 3 did not run third." }
foreach ($result in @($step1, $step2, $step3)) {
  if ([int]$result.selected_step_count -ne 1 -or [int]$result.selected_task_count -ne 1) { throw "Each apply-next must select one step/task." }
  if ([int]$result.task_claimed_count -ne 1 -or [int]$result.execution_completed_count -ne 1) { throw "Each apply-next must complete one task." }
  Assert-False $result.codex_run_called "codex_run_called"
  Assert-False $result.matlab_run_called "matlab_run_called"
  Assert-False $result.hermes_run_called "hermes_run_called"
  Assert-False $result.mcp_run_called "mcp_run_called"
  Assert-False $result.worker_loop_started "worker_loop_started"
  Assert-False $result.project_control_unpaused "project_control_unpaused"
  Assert-TokenPrintedFalse $result
}
Assert-True $step3.campaign_completed "campaign_completed"
if (@($step3.steps | Where-Object { $_.completed -eq $true }).Count -ne 3) { throw "Expected all steps completed." }
if (@($step3.steps | Where-Object { $_.evidence_attached -eq $true }).Count -ne 3) { throw "Expected evidence on all steps." }

Complete-Smoke "multi-goal-loop-fixture-all"
