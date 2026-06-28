. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-reject-no-confirm-$([guid]::NewGuid().ToString('N'))"
$approveResult = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approval reason without exact confirmation."
)
if (-not (@($approveResult.blockers) -contains "missing_approve_confirmation")) { throw "Approve did not reject missing confirmation." }
Assert-False $approveResult.import_performed "approve import_performed"
Assert-False $approveResult.approval_performed "approve approval_performed"
Assert-False $approveResult.append_performed "approve append_performed"
Assert-TokenPrintedFalse $approveResult

$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $approveConfirm
) | Out-Null

$appendResult = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "append-apply",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-AppendReason", "Operator appended fixture metadata only."
)
if (-not (@($appendResult.blockers) -contains "missing_append_confirmation")) { throw "Append did not reject missing confirmation." }
Assert-False $appendResult.append_applied "append_applied"
Assert-False $appendResult.append_performed "append_performed"
Assert-False $appendResult.task_created "task_created"
Assert-False $appendResult.task_claimed "task_claimed"
Assert-False $appendResult.execution_started "execution_started"
Assert-TokenPrintedFalse $appendResult

$campaignState = Join-Path (Join-Path $RepoRoot $outputDir) "campaign-state.json"
if (Test-Path -LiteralPath $campaignState) { throw "append without confirmation wrote campaign state." }

Complete-Smoke "goal-append-reject-no-confirm"
