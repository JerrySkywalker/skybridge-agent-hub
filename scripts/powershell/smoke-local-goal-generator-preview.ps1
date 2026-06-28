. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-preview-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "preview", "-Fixture", "-OutputDir", $outputDir)
$goalPath = Join-Path $RepoRoot $result.generated_goal_path_safe
if (Test-Path -LiteralPath $goalPath) { throw "Preview wrote generated markdown." }
Assert-True $result.generated_goal_schema_valid "generated_goal_schema_valid"
Assert-True $result.generated_goal_safety_valid "generated_goal_safety_valid"
Assert-False $result.proposed_goal_written "proposed_goal_written"
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-preview"
