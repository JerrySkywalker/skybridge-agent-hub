. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-goal-append.ps1" @("-Command", "status", "-Fixture")
if ([string]$result.schema -ne "skybridge.goal_append_review.v1") { throw "Unexpected goal append schema." }
if ([string]$result.mode -ne "fixture") { throw "Expected fixture mode." }
Assert-True $result.metadata_valid "metadata_valid"
Assert-True $result.safety_valid "safety_valid"
Assert-True $result.human_review_required "human_review_required"
Assert-False $result.import_allowed "import_allowed"
Assert-False $result.execution_allowed "execution_allowed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "goal-append-status"
