. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-reject-unsafe-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @(
  "-Command", "generate-one",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-GeneratedGoalDir", "goals/ready",
  "-GoalId", "../bad",
  "-Objective", "production deploy with arbitrary shell",
  "-Confirm", $confirm
)
foreach ($expected in @("unsafe_goal_id", "unsafe_objective", "output_dir_outside_allowed_root")) {
  if (-not (@($result.blockers) -contains $expected)) { throw "Missing unsafe blocker: $expected" }
}
Assert-False $result.proposed_goal_written "proposed_goal_written"
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-reject-unsafe"
