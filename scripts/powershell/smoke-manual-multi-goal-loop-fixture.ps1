. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/manual-multi-goal-loop-smoke-$([guid]::NewGuid().ToString('N'))"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-multi-goal-loop-test.ps1") -Fixture -ApplyNext -Confirm "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY" -OutputDir $outputDir -Json
if ($LASTEXITCODE -ne 0) { throw "manual-multi-goal-loop-test failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)
if ($result.milestone -ne "M3: Multi-Step Static Campaign Manual Test") { throw "Unexpected milestone." }
Assert-True $result.checklist.one_campaign "one_campaign"
Assert-True $result.checklist.three_steps "three_steps"
Assert-True $result.checklist.one_step_candidate "one_step_candidate"
Assert-True $result.checklist.one_task_per_apply_next "one_task_per_apply_next"
Assert-True $result.checklist.task_completed_this_apply "task_completed_this_apply"
Assert-True $result.checklist.evidence_attached_this_apply "evidence_attached_this_apply"
Assert-True $result.checklist.no_codex_matlab_hermes_mcp_in_fixture "no_codex_matlab_hermes_mcp_in_fixture"
Assert-True $result.checklist.no_unbounded_loop "no_unbounded_loop"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-multi-goal-loop-fixture"
