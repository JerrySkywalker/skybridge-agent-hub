[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-draft-submit-common.ps1"

$ConfirmationPhrase = "I_UNDERSTAND_CREATE_QUEUED_DRAFT_RECORDS_ONLY_NO_EXECUTION"

try {
  Start-DraftSubmitSmokeServer | Out-Null
  $docsFile = New-DraftSubmitInputFile -Kind "sample-docs"

  $missingConfirm = Invoke-DraftSubmitScript -Command "submit" -InputJsonFile $docsFile
  if ($missingConfirm.ok -ne $false) { throw "Submit without confirmation should be rejected." }
  if ([string]$missingConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing confirmation rejection reason mismatch." }
  Assert-False $missingConfirm.task_created "missing confirmation task_created"
  Assert-DraftSubmitDisabledFlags $missingConfirm "missing confirmation"

  $submitted = Invoke-DraftSubmitScript -Command "submit" -InputJsonFile $docsFile -Confirm -ConfirmationText $ConfirmationPhrase
  if ([string]$submitted.schema -ne "skybridge.draft_submit_result.v1") { throw "Unexpected submit result schema." }
  if ($submitted.task_created -ne $true) { throw "Confirmed docs draft did not create a task." }
  Assert-False $submitted.campaign_created "docs submit campaign_created"
  Assert-DraftSubmitDisabledFlags $submitted "docs submit"

  $tasks = Invoke-DraftSubmitJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  if (@($tasks.tasks).Count -ne 1) { throw "Expected exactly one queued task." }
  $task = @($tasks.tasks)[0]
  if ([string]$task.status -ne "queued") { throw "Submitted task must remain queued." }
  if ($task.assigned_worker_id) { throw "Submitted task must not be assigned." }
  if ([string]$task.planner_metadata.reason -ne "draft_review_submit_queued_only_no_execution") { throw "Planner metadata reason mismatch." }

  $unknownFile = New-DraftSubmitInputFile -Kind "unknown-template"
  $unknown = Invoke-DraftSubmitScript -Command "preview" -InputJsonFile $unknownFile
  if ($unknown.ok -ne $false) { throw "Unknown template should be rejected." }
  if (@($unknown.blockers) -notcontains "unknown_template_id") { throw "Unknown template blocker missing." }
  Assert-DraftSubmitDisabledFlags $unknown "unknown template"

  $unsafeFile = New-DraftSubmitInputFile -Kind "unsafe"
  $unsafe = Invoke-DraftSubmitScript -Command "preview" -InputJsonFile $unsafeFile
  if ($unsafe.ok -ne $false) { throw "Unsafe draft should be rejected." }
  if (@($unsafe.blockers) -notcontains "draft_not_submittable") { throw "Unsafe draft submit blocker missing." }
  Assert-DraftSubmitDisabledFlags $unsafe "unsafe draft"

  [pscustomobject]@{
    ok = $true
    smoke = "draft-submit-server"
    created_task_id = $submitted.created_task_id
    task_status = $task.status
    submit_without_confirmation_rejected = $true
    unknown_template_rejected = $true
    unsafe_request_rejected = $true
    task_created = $true
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpause = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-DraftSubmitSmokeServer
}
