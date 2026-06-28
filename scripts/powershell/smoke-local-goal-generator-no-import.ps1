. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-no-import-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "generate-one", "-Fixture", "-OutputDir", $outputDir, "-Confirm", $confirm)
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-no-import"
