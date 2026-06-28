. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-manual-$([guid]::NewGuid().ToString('N'))"
$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$appendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"

$previewRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-goal-append-review-test.ps1") -Fixture -ReviewPreview -OutputDir $outputDir -Json
if ($LASTEXITCODE -ne 0) { throw "manual review-preview failed." }
$preview = (($previewRaw | Out-String).Trim() | ConvertFrom-Json)
if ([string]$preview.schema -ne "skybridge.goal_append_manual_test.v1") { throw "Unexpected manual schema." }
Assert-True $preview.metadata_valid "preview metadata_valid"
Assert-True $preview.safety_valid "preview safety_valid"
Assert-False $preview.import_performed "preview import_performed"

$approveRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-goal-append-review-test.ps1") -Fixture -Approve -OutputDir $outputDir -ApprovalReason "Operator approved fixture metadata review only." -Confirm $approveConfirm -Json
if ($LASTEXITCODE -ne 0) { throw "manual approve failed." }
$approve = (($approveRaw | Out-String).Trim() | ConvertFrom-Json)
Assert-True $approve.approved "approved"
Assert-True $approve.approval_performed "approval_performed"

$appendPreviewRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-goal-append-review-test.ps1") -Fixture -AppendPreview -OutputDir $outputDir -Json
if ($LASTEXITCODE -ne 0) { throw "manual append-preview failed." }
$appendPreview = (($appendPreviewRaw | Out-String).Trim() | ConvertFrom-Json)
Assert-True $appendPreview.append_preview_valid "append_preview_valid"
Assert-False $appendPreview.append_performed "append_preview append_performed"

$appendRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-goal-append-review-test.ps1") -Fixture -AppendApply -OutputDir $outputDir -AppendReason "Operator appended fixture metadata only." -Confirm $appendConfirm -Json
if ($LASTEXITCODE -ne 0) { throw "manual append-apply failed." }
$result = (($appendRaw | Out-String).Trim() | ConvertFrom-Json)
Assert-True $result.append_applied "append_applied"
Assert-True $result.append_performed "append_performed"
if ([string]$result.appended_step_state -ne "pending") { throw "Unexpected appended step state." }
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-goal-append-fixture"
