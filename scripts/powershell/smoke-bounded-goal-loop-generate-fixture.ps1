. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/bounded-goal-loop/smoke-generate-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "generate",
  "-OutputDir", $outputDir,
  "-Confirm", $confirm
)
if ([string]$result.selected_action -ne "generate_proposed_goal") { throw "Unexpected selected action." }
Assert-True $result.action_performed "action_performed"
Assert-True $result.goal_generated "goal_generated"
Assert-False $result.goal_reviewed "goal_reviewed"
Assert-False $result.goal_appended "goal_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
if ([int]$result.goal_budget_remaining_before -ne 1 -or [int]$result.goal_budget_remaining_after -ne 1) { throw "Generation should not consume budget." }
if ([string]$result.generated_goal_id -ne "bounded-loop-generated-goal-356-fixture") { throw "Unexpected generated goal id." }
if ([string]$result.selected_candidate_hash -notmatch "^[a-f0-9]{64}$") { throw "Generated hash missing." }
Assert-FileExists $result.generated_goal_path_safe
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.generated_goal_path_safe)
Assert-NoUnsafeText $text
if ($text -notmatch "human_review_required") { throw "Generated markdown missing review metadata." }
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-generate-fixture"
