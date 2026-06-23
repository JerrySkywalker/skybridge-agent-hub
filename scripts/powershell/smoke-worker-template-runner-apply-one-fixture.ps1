[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$ConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_SAFE_TEMPLATE_TASK_ONLY"

try {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  $seed = Seed-WorkerTemplateRunnerFixture

  $missingConfirm = Invoke-WorkerTemplateRunnerScript -Command "apply-one" -ProjectId $seed.project_id
  if ($missingConfirm.ok -ne $false) { throw "apply-one without confirmation should be rejected." }
  if ([string]$missingConfirm.rejected_reason -ne "missing_exact_confirmation") { throw "Missing confirmation rejection reason mismatch." }
  Assert-True $missingConfirm.selected "missing confirmation selected"
  Assert-RunnerNoClaimOrExecution $missingConfirm "missing confirmation"

  $taskAfterMissingConfirm = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/$([uri]::EscapeDataString($seed.task_id))").task
  if ([string]$taskAfterMissingConfirm.status -ne "queued") { throw "Missing confirmation mutated task status." }
  if ($taskAfterMissingConfirm.claim) { throw "Missing confirmation created a claim." }

  $tooMany = Invoke-WorkerTemplateRunnerScript -Command "apply-one" -ProjectId $seed.project_id -MaxTasks 2 -Confirm -ConfirmationText $ConfirmationPhrase
  if ($tooMany.ok -ne $false) { throw "apply-one with MaxTasks > 1 should be rejected." }
  if ([string]$tooMany.rejected_reason -ne "max_tasks_exceeds_mg329_limit") { throw "MaxTasks rejection reason mismatch." }
  Assert-RunnerNoClaimOrExecution $tooMany "max tasks"

  $applied = Invoke-WorkerTemplateRunnerScript -Command "apply-one" -ProjectId $seed.project_id -Confirm -ConfirmationText $ConfirmationPhrase
  if ([string]$applied.schema -ne "skybridge.worker_template_runner_result.v1") { throw "Unexpected runner result schema." }
  if ($applied.ok -ne $true) { throw "Confirmed apply-one failed: $($applied.rejected_reason)" }
  Assert-True $applied.claim_created "apply claim_created"
  Assert-True $applied.execution_started "apply execution_started"
  Assert-True $applied.execution_completed "apply execution_completed"
  Assert-False $applied.execution_failed "apply execution_failed"
  Assert-True $applied.evidence_present "apply evidence_present"
  Assert-True $applied.allowed_paths_checked "apply allowed_paths_checked"
  Assert-True $applied.blocked_paths_checked "apply blocked_paths_checked"
  Assert-RunnerForbiddenFlagsFalse $applied "apply"
  if ([string]$applied.validation_status -ne "passed") { throw "Apply validation status mismatch." }

  $task = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/$([uri]::EscapeDataString($seed.task_id))").task
  if ([string]$task.status -ne "completed") { throw "Task should be completed after fixture apply-one." }
  if ([string]$task.assigned_worker_id -ne [string]$seed.worker_id) { throw "Task assigned worker mismatch." }
  if ([string]$task.lease.lease_status -ne "released") { throw "Task lease should be released." }
  if (-not $task.result.evidence_summary) { throw "Task result evidence summary missing." }
  if ([string]$task.result.evidence_summary.validation_status -ne "passed") { throw "Task evidence validation status mismatch." }
  $eventTypes = @($task.events | ForEach-Object { [string]$_.type })
  foreach ($eventType in @("task.claimed", "task.started", "task.completed")) {
    if ($eventTypes -notcontains $eventType) { throw "Missing task event: $eventType" }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-template-runner-apply-one-fixture"
    schema = $applied.schema
    task_id = $applied.task_id
    template_id = $applied.template_id
    runner_id = $applied.runner_id
    task_status = $task.status
    lease_status = $task.lease.lease_status
    missing_confirmation_rejected = $true
    max_tasks_over_one_rejected = $true
    claim_created = $true
    execution_started = $true
    execution_completed = $true
    execution_failed = $false
    evidence_present = $true
    pr_created = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    old_task_requeued = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}
