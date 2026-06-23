[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-heartbeat-pairing-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
$installConfirmation = "I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION"
$heartbeatConfirmation = "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM"
$workerId = "mg330-heartbeat-fixture-worker"

try {
  $apiBase = Start-WorkerTemplateRunnerSmokeServer
  $installRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-install.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -ApiBase $apiBase -WorkerId $workerId -Fixture -Confirm -ConfirmationText $installConfirmation -Json
  $installText = ($installRaw | Out-String).Trim()
  Assert-NoUnsafeText $installText
  $install = $installText | ConvertFrom-Json
  Assert-True $install.ok "heartbeat fixture install ok"

  $workersBefore = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  $workerCountBefore = @($workersBefore.workers).Count

  $previewRaw = & (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-pairing-drill.ps1") -Command heartbeat-preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId $workerId -Json
  $previewText = ($previewRaw | Out-String).Trim()
  Assert-NoUnsafeText $previewText
  $preview = $previewText | ConvertFrom-Json
  if ([string]$preview.schema -ne "skybridge.worker_heartbeat_pairing_drill.v1") { throw "Unexpected heartbeat preview schema." }
  Assert-True $preview.ok "heartbeat preview ok"
  Assert-False $preview.would_mutate_server "heartbeat preview would_mutate_server"
  Assert-False $preview.server_mutation_performed "heartbeat preview server_mutation_performed"
  Assert-TokenPrintedFalse $preview

  $workersAfterPreview = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  if (@($workersAfterPreview.workers).Count -ne $workerCountBefore) { throw "Heartbeat preview mutated fixture server workers." }

  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-pairing-drill.ps1") -Command heartbeat-apply -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId $workerId -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ($missing.ok -ne $false) { throw "Heartbeat apply without confirmation should be rejected." }
  if ([string]$missing.review_reason -ne "missing_exact_confirmation") { throw "Heartbeat missing confirmation reason mismatch." }
  Assert-False $missing.server_mutation_performed "heartbeat missing confirmation server_mutation_performed"
  Assert-TokenPrintedFalse $missing

  $workersAfterMissingConfirm = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  if (@($workersAfterMissingConfirm.workers).Count -ne $workerCountBefore) { throw "Rejected heartbeat apply mutated fixture server workers." }

  $applyRaw = & (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-pairing-drill.ps1") -Command heartbeat-apply -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId $workerId -Confirm -ConfirmationText $heartbeatConfirmation -Json
  $applyText = ($applyRaw | Out-String).Trim()
  Assert-NoUnsafeText $applyText
  if ($applyText -match "fixture-local-auth-value") { throw "Fixture token value was printed." }
  $apply = $applyText | ConvertFrom-Json
  Assert-True $apply.ok "heartbeat apply ok"
  Assert-True $apply.server_mutation_performed "heartbeat apply server_mutation_performed"
  Assert-True $apply.cloud_worker_registered "heartbeat apply cloud_worker_registered"
  Assert-True $apply.cloud_worker_online "heartbeat apply cloud_worker_online"
  Assert-False $apply.claim_enabled "heartbeat apply claim_enabled"
  Assert-False $apply.execute_enabled "heartbeat apply execute_enabled"
  Assert-False $apply.template_runner_enabled "heartbeat apply template_runner_enabled"
  Assert-False $apply.claim_created "heartbeat apply claim_created"
  Assert-False $apply.execution_started "heartbeat apply execution_started"
  Assert-False $apply.worker_loop_started "heartbeat apply worker_loop_started"
  Assert-False $apply.codex_run_called "heartbeat apply codex_run_called"
  Assert-False $apply.matlab_run_called "heartbeat apply matlab_run_called"
  Assert-False $apply.arbitrary_shell_enabled "heartbeat apply arbitrary_shell_enabled"
  Assert-False $apply.project_control_unpaused "heartbeat apply project_control_unpaused"
  Assert-TokenPrintedFalse $apply

  $workersAfterApply = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  $worker = @($workersAfterApply.workers | Where-Object { [string]$_.worker_id -eq $workerId })[0]
  if (-not $worker) { throw "Heartbeat fixture worker was not registered." }
  if ([string]$worker.status -ne "online") { throw "Heartbeat fixture worker should be online." }
  if ($worker.current_task_id) { throw "Heartbeat fixture worker should not have a current task." }

  $tasks = Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  if (@($tasks.tasks).Count -ne 0) { throw "Heartbeat fixture should not create or claim tasks." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-heartbeat-pairing-fixture"
    schema = $apply.schema
    register_status_code = $apply.register_status_code
    heartbeat_status_code = $apply.heartbeat_status_code
    worker_status = $worker.status
    preview_created_worker = $false
    missing_confirmation_rejected = $true
    task_count = 0
    claim_enabled = $false
    execute_enabled = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
