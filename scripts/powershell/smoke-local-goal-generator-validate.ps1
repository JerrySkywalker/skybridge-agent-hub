. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-validate-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$generated = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "generate-one", "-Fixture", "-OutputDir", $outputDir, "-Confirm", $confirm)
$validated = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "validate-generated", "-Fixture", "-OutputDir", $outputDir)
if ([string]$validated.generated_goal_hash -ne [string]$generated.generated_goal_hash) { throw "Validation hash mismatch." }
Assert-True $validated.generated_goal_schema_valid "generated_goal_schema_valid"
Assert-True $validated.generated_goal_safety_valid "generated_goal_safety_valid"
Assert-False $validated.codex_generation_called "codex_generation_called"
Assert-False $validated.import_performed "import_performed"
Assert-False $validated.approval_performed "approval_performed"
Assert-False $validated.append_performed "append_performed"
Assert-False $validated.execution_started "execution_started"
Assert-TokenPrintedFalse $validated

Complete-Smoke "local-goal-generator-validate"
