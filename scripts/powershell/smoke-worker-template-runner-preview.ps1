[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

try {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  $seed = Seed-WorkerTemplateRunnerFixture

  $preview = Invoke-WorkerTemplateRunnerScript -Command "preview" -ProjectId $seed.project_id
  if ([string]$preview.schema -ne "skybridge.worker_template_runner_preview.v1") { throw "Unexpected runner preview schema." }
  if ($preview.ok -ne $true) { throw "Runner preview did not select the safe fixture task: $($preview.rejected_reason)" }
  Assert-True $preview.selected "preview selected"
  Assert-True $preview.eligible "preview eligible"
  Assert-True $preview.allowed_paths_checked "preview allowed_paths_checked"
  Assert-True $preview.blocked_paths_checked "preview blocked_paths_checked"
  Assert-RunnerNoClaimOrExecution $preview "preview"
  if ([string]$preview.template_id -ne "safe-local-smoke.v1") { throw "Preview selected unexpected template." }
  if ([string]$preview.runner_id -ne "safe-local-smoke-runner.v1") { throw "Preview selected unexpected runner." }

  $task = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/$([uri]::EscapeDataString($seed.task_id))").task
  if ([string]$task.status -ne "queued") { throw "Preview mutated task status." }
  if ($task.claim) { throw "Preview created a task claim." }
  if ($task.assigned_worker_id) { throw "Preview assigned a worker." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-template-runner-preview"
    schema = $preview.schema
    selected_task_id = $preview.task_id
    selected_template_id = $preview.template_id
    selected_runner_id = $preview.runner_id
    preview_created_claim = $false
    task_status_after_preview = $task.status
    claim_created = $false
    execution_started = $false
    execution_completed = $false
    execution_failed = $false
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
