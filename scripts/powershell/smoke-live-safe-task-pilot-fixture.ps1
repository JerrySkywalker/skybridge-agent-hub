[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$CreateConfirmation = "I_UNDERSTAND_CREATE_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"
$RunConfirmation = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"

function Invoke-LiveSafeTaskPilot {
  param(
    [string]$Command,
    [switch]$Confirm,
    [string]$ConfirmationText = ""
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-live-safe-task-pilot.ps1"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $scriptPath,
    "-Command",
    $Command,
    "-ApiBase",
    $script:WorkerTemplateRunnerApiBase,
    "-WorkerId",
    "jerry-win-local-01",
    "-ProjectId",
    "skybridge-agent-hub",
    "-TaskId",
    "live-safe-template-task-332-001",
    "-TemplateId",
    "safe-local-smoke.v1",
    "-Json"
  )
  if ($Confirm) { $args += "-Confirm" }
  if (-not [string]::IsNullOrWhiteSpace($ConfirmationText)) { $args += @("-ConfirmationText", $ConfirmationText) }
  $raw = & pwsh @args
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG332 Live Safe Task Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "node")
    labels = @("mg332-fixture", "safe-local-smoke")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{
    status_note = "mg332 fixture ready"
    load = 0
  } | Out-Null

  $missingCreateConfirm = Invoke-LiveSafeTaskPilot -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false) { throw "apply-create without confirmation should be rejected." }
  if ([string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing create confirmation reason mismatch." }
  Assert-False $missingCreateConfirm.task_created "missing create confirmation task_created"
  Assert-False $missingCreateConfirm.claim_created "missing create confirmation claim_created"
  Assert-TokenPrintedFalse $missingCreateConfirm

  $created = Invoke-LiveSafeTaskPilot -Command "apply-create" -Confirm -ConfirmationText $CreateConfirmation
  if ($created.ok -ne $true) { throw "apply-create with confirmation failed: $($created.review_reason)" }
  Assert-True $created.task_created "created task_created"
  Assert-False $created.claim_created "created claim_created"
  Assert-False $created.execution_started "created execution_started"
  Assert-TokenPrintedFalse $created

  $taskAfterCreate = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/live-safe-template-task-332-001").task
  if ([string]$taskAfterCreate.status -ne "queued") { throw "Created task should be queued." }
  if ($taskAfterCreate.claim) { throw "Created task should not be claimed." }

  $previewRun = Invoke-LiveSafeTaskPilot -Command "preview-run"
  if ($previewRun.ok -ne $true) { throw "preview-run should select the exact fixture task: $($previewRun.rejected_reason)" }
  if ([string]$previewRun.task_id -ne "live-safe-template-task-332-001") { throw "preview selected unexpected task." }
  Assert-False $previewRun.claim_created "preview-run claim_created"
  Assert-False $previewRun.execution_started "preview-run execution_started"
  Assert-RunnerForbiddenFlagsFalse $previewRun "preview-run"

  $missingRunConfirm = Invoke-LiveSafeTaskPilot -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should be rejected." }
  if ([string]$missingRunConfirm.runner_result.rejected_reason -ne "missing_exact_confirmation") { throw "Missing run confirmation reason mismatch." }
  Assert-False $missingRunConfirm.claim_created "missing run confirmation claim_created"
  Assert-False $missingRunConfirm.execution_started "missing run confirmation execution_started"
  Assert-TokenPrintedFalse $missingRunConfirm

  $taskAfterMissingRunConfirm = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/live-safe-template-task-332-001").task
  if ([string]$taskAfterMissingRunConfirm.status -ne "queued") { throw "Missing run confirmation mutated task status." }
  if ($taskAfterMissingRunConfirm.claim) { throw "Missing run confirmation created claim." }

  $applied = Invoke-LiveSafeTaskPilot -Command "apply-run" -Confirm -ConfirmationText $RunConfirmation
  if ($applied.ok -ne $true) { throw "apply-run with confirmation failed: $($applied.runner_result.rejected_reason)" }
  Assert-True $applied.claim_created "apply-run claim_created"
  Assert-True $applied.execution_started "apply-run execution_started"
  Assert-True $applied.execution_completed "apply-run execution_completed"
  Assert-False $applied.execution_failed "apply-run execution_failed"
  if ([int]$applied.task_claimed_count -ne 1) { throw "Expected task_claimed_count=1." }
  Assert-False $applied.old_task_claimed "apply-run old_task_claimed"
  Assert-False $applied.codex_run_called "apply-run codex_run_called"
  Assert-False $applied.matlab_run_called "apply-run matlab_run_called"
  Assert-False $applied.arbitrary_shell_enabled "apply-run arbitrary_shell_enabled"
  Assert-False $applied.worker_loop_started "apply-run worker_loop_started"
  Assert-False $applied.project_control_unpaused "apply-run project_control_unpaused"
  Assert-TokenPrintedFalse $applied

  $task = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/live-safe-template-task-332-001").task
  if ([string]$task.status -ne "completed") { throw "Task should be completed after fixture apply-run." }
  if ([string]$task.assigned_worker_id -ne "jerry-win-local-01") { throw "Task assigned worker mismatch." }
  if (-not $task.result.evidence_summary) { throw "Task evidence summary missing." }
  if ([string]$task.result.evidence_summary.validation_status -ne "passed") { throw "Task evidence validation status mismatch." }
  $eventTypes = @($task.events | ForEach-Object { [string]$_.type })
  foreach ($eventType in @("task.claimed", "task.started", "task.completed")) {
    if ($eventTypes -notcontains $eventType) { throw "Missing task event: $eventType" }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "live-safe-task-pilot-fixture"
    task_id = "live-safe-template-task-332-001"
    final_task_state = $task.status
    missing_create_confirmation_rejected = $true
    missing_run_confirmation_rejected = $true
    task_claimed_count = 1
    old_task_claimed = $false
    claim_created = $true
    execution_started = $true
    execution_completed = $true
    execution_failed = $false
    evidence_present = $true
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}
