. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-manual-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-local-goal-generate-test.ps1") -Fixture -GenerateOne -OutputDir $outputDir -Confirm $confirm -Json
if ($LASTEXITCODE -ne 0) { throw "manual-local-goal-generate-test.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)
if ([string]$result.schema -ne "skybridge.local_goal_generator_manual_test.v1") { throw "Unexpected manual test schema." }
Assert-True $result.generated_metadata_valid "generated_metadata_valid"
Assert-True $result.generated_safety_valid "generated_safety_valid"
Assert-True $result.human_review_required "human_review_required"
Assert-False $result.import_allowed "import_allowed"
Assert-False $result.execution_allowed "execution_allowed"
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-local-goal-generator-fixture"
