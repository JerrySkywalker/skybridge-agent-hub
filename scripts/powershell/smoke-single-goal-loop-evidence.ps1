. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/single-goal-loop-smoke"
$result = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY", "-WriteReport", "-OutputDir", $outputDir)
if ($result.evidence.schema -ne "skybridge.single_goal_loop_evidence.v1") { throw "Unexpected evidence schema." }
if ($result.evidence.task_claimed_count -ne 1) { throw "Expected evidence task_claimed_count=1." }
Assert-True $result.evidence.provider_inventory_checked "evidence.provider_inventory_checked"
Assert-True $result.evidence.direct_provider_available "evidence.direct_provider_available"
Assert-False $result.evidence.execution_failed "evidence.execution_failed"
Assert-False $result.evidence.codex_run_called "evidence.codex_run_called"
Assert-False $result.evidence.matlab_run_called "evidence.matlab_run_called"
Assert-False $result.evidence.hermes_run_called "evidence.hermes_run_called"
Assert-False $result.evidence.mcp_run_called "evidence.mcp_run_called"
Assert-False $result.evidence.worker_loop_started "evidence.worker_loop_started"
Assert-TokenPrintedFalse $result.evidence
Assert-FileExists "$outputDir/single-goal-loop.json"
Assert-FileExists "$outputDir/single-goal-loop.md"
$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/single-goal-loop.json")
Assert-NoUnsafeText $reportText

Complete-Smoke "single-goal-loop-evidence"
