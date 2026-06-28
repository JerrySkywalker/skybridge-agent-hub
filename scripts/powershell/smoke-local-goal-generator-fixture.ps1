. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-fixture-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "generate-one", "-Fixture", "-OutputDir", $outputDir, "-Confirm", $confirm)
$goalPath = Join-Path $RepoRoot $result.generated_goal_path_safe
if (-not (Test-Path -LiteralPath $goalPath -PathType Leaf)) { throw "Fixture did not write generated markdown." }
if ([string]$result.generated_goal_id -ne "generated-docs-validation-goal-354-fixture") { throw "Unexpected generated goal id." }
if ([string]$result.generated_goal_hash -notmatch "^[0-9a-f]{64}$") { throw "Generated goal hash missing." }
Assert-True $result.generated_goal_schema_valid "generated_goal_schema_valid"
Assert-True $result.generated_goal_safety_valid "generated_goal_safety_valid"
Assert-True $result.proposed_goal_written "proposed_goal_written"
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

$markdown = Get-Content -Raw -LiteralPath $goalPath
foreach ($required in @("skybridge.generated_goal_metadata.v1", "human_review_required", "import_allowed", "execution_allowed", "## No-Execution Statement")) {
  if ($markdown -notmatch [regex]::Escape($required)) { throw "Generated markdown missing $required." }
}

Complete-Smoke "local-goal-generator-fixture"
