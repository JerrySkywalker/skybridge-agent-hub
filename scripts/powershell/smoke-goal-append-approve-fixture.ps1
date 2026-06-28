. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-approve-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $confirm
)
Assert-True $result.approved "approved"
Assert-False $result.rejected "rejected"
Assert-True $result.import_performed "import_performed"
Assert-True $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

$reviewState = Join-Path (Join-Path $RepoRoot $outputDir) "review-state\review-state.json"
if (-not (Test-Path -LiteralPath $reviewState -PathType Leaf)) { throw "Approve did not write review state." }

Complete-Smoke "goal-append-approve-fixture"
