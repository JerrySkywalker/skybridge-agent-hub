. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-append-apply-$([guid]::NewGuid().ToString('N'))"
$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$appendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $approveConfirm
) | Out-Null

$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "append-apply",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-AppendReason", "Operator appended fixture metadata only.",
  "-Confirm", $appendConfirm
)
Assert-True $result.append_preview_valid "append_preview_valid"
Assert-True $result.append_applied "append_applied"
Assert-True $result.append_performed "append_performed"
Assert-True $result.import_performed "import_performed"
if ([string]$result.appended_step_id -ne "appended-generated-goal-355-fixture-step") { throw "Unexpected appended step id." }
if ([string]$result.appended_step_state -ne "pending") { throw "Unexpected appended step state." }
if ([int]$result.goal_budget_remaining_before -ne 1) { throw "Unexpected budget before." }
if ([int]$result.goal_budget_remaining_after -ne 0) { throw "Unexpected budget after." }
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

$campaignStatePath = Join-Path (Join-Path $RepoRoot $outputDir) "campaign-state.json"
if (-not (Test-Path -LiteralPath $campaignStatePath -PathType Leaf)) { throw "append-apply did not write campaign state." }
$campaignState = Get-Content -Raw -LiteralPath $campaignStatePath | ConvertFrom-Json
if (@($campaignState.steps).Count -ne 1) { throw "append-apply wrote more than one step." }
Assert-False $campaignState.steps[0].task_created "campaign step task_created"
Assert-False $campaignState.steps[0].execution_started "campaign step execution_started"

Complete-Smoke "goal-append-append-apply-fixture"
