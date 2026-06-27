. "$PSScriptRoot\smoke-productization-common.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-single-goal-loop-test.ps1") -Fixture -Apply -Confirm "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY" -Json
if ($LASTEXITCODE -ne 0) { throw "manual-single-goal-loop-test failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)
if ($result.milestone -ne "M2: Single Goal Loop Manual Test") { throw "Unexpected milestone." }
Assert-True $result.checklist.one_campaign "one_campaign"
Assert-True $result.checklist.one_step "one_step"
Assert-True $result.checklist.one_safe_local_smoke_task_candidate "one_safe_local_smoke_task_candidate"
Assert-True $result.checklist.task_completed "task_completed"
Assert-True $result.checklist.evidence_attached "evidence_attached"
Assert-True $result.checklist.step_completed "step_completed"
Assert-True $result.checklist.campaign_completed_or_held "campaign_completed_or_held"
Assert-False $result.checklist.codex_run_called "codex_run_called"
Assert-False $result.checklist.matlab_run_called "matlab_run_called"
Assert-False $result.checklist.hermes_run_called "hermes_run_called"
Assert-False $result.checklist.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-single-goal-loop-fixture"
