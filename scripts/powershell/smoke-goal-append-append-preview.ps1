. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-append-preview-$([guid]::NewGuid().ToString('N'))"
$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $approveConfirm
) | Out-Null

$result = Invoke-JsonScript "skybridge-goal-append.ps1" @("-Command", "append-preview", "-Fixture", "-OutputDir", $outputDir)
Assert-True $result.append_preview_valid "append_preview_valid"
Assert-False $result.append_applied "append_applied"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

$campaignState = Join-Path (Join-Path $RepoRoot $outputDir) "campaign-state.json"
if (Test-Path -LiteralPath $campaignState) { throw "append-preview wrote campaign state." }

Complete-Smoke "goal-append-append-preview"
