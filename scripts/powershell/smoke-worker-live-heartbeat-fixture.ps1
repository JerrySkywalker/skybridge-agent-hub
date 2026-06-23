[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-live-heartbeat-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
$identityConfirmation = "I_UNDERSTAND_CONFIGURE_LOCAL_WORKER_IDENTITY_NO_TASK_EXECUTION"
$heartbeatConfirmation = "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM"
$workerId = "jerry-win-local-01"

try {
  $apiBase = Start-WorkerTemplateRunnerSmokeServer
  $skybridgeDir = Join-Path $tempHome ".skybridge"
  New-Item -ItemType Directory -Path $skybridgeDir -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $skybridgeDir "skybridge.env.ps1") -Value "`$env:SKYBRIDGE_API_BASE = '$apiBase'" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $skybridgeDir "worker-token.txt") -Value "fixture-local-auth-value" -NoNewline -Encoding UTF8

  $identityRaw = & (Join-Path $PSScriptRoot "skybridge-worker-identity.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId $workerId -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Confirm -ConfirmationText $identityConfirmation -Json
  $identityText = ($identityRaw | Out-String).Trim()
  Assert-NoUnsafeText $identityText
  $identity = $identityText | ConvertFrom-Json
  Assert-True $identity.ok "live heartbeat fixture identity apply ok"

  $workersBefore = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  $workerCountBefore = @($workersBefore.workers).Count

  $previewRaw = & (Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $previewText = ($previewRaw | Out-String).Trim()
  Assert-NoUnsafeText $previewText
  $preview = $previewText | ConvertFrom-Json
  if ([string]$preview.schema -ne "skybridge.worker_live_heartbeat.v1") { throw "Unexpected live heartbeat preview schema." }
  Assert-True $preview.ok "live heartbeat preview ok"
  Assert-False $preview.would_mutate_server "live heartbeat preview would_mutate_server"
  Assert-False $preview.server_mutation_performed "live heartbeat preview server_mutation_performed"
  Assert-TokenPrintedFalse $preview

  $workersAfterPreview = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  if (@($workersAfterPreview.workers).Count -ne $workerCountBefore) { throw "Live heartbeat preview mutated fixture server workers." }

  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ($missing.ok -ne $false) { throw "Live heartbeat apply without confirmation should be rejected." }
  if ([string]$missing.review_reason -ne "missing_exact_confirmation") { throw "Live heartbeat missing confirmation reason mismatch." }
  Assert-False $missing.server_mutation_performed "live heartbeat missing confirmation server_mutation_performed"
  Assert-TokenPrintedFalse $missing

  $workersAfterMissingConfirm = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  if (@($workersAfterMissingConfirm.workers).Count -ne $workerCountBefore) { throw "Rejected live heartbeat apply mutated fixture server workers." }

  $applyRaw = & (Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -Confirm -ConfirmationText $heartbeatConfirmation -Json
  $applyText = ($applyRaw | Out-String).Trim()
  Assert-NoUnsafeText $applyText
  if ($applyText -match "fixture-local-auth-value") { throw "Fixture token value was printed." }
  $apply = $applyText | ConvertFrom-Json
  Assert-True $apply.ok "live heartbeat apply ok"
  Assert-True $apply.server_mutation_performed "live heartbeat apply server_mutation_performed"
  Assert-True $apply.worker_registered "live heartbeat worker_registered"
  Assert-True $apply.heartbeat_sent "live heartbeat heartbeat_sent"
  Assert-True $apply.cloud_worker_seen "live heartbeat cloud_worker_seen"
  if ([string]$apply.cloud_worker_status -ne "online") { throw "Live heartbeat fixture worker should be online." }
  Assert-False $apply.claim_enabled "live heartbeat claim_enabled"
  Assert-False $apply.execute_enabled "live heartbeat execute_enabled"
  Assert-False $apply.template_runner_enabled "live heartbeat template_runner_enabled"
  Assert-False $apply.claim_created "live heartbeat claim_created"
  Assert-False $apply.execution_started "live heartbeat execution_started"
  Assert-False $apply.worker_loop_started "live heartbeat worker_loop_started"
  Assert-False $apply.codex_run_called "live heartbeat codex_run_called"
  Assert-False $apply.matlab_run_called "live heartbeat matlab_run_called"
  Assert-False $apply.arbitrary_shell_enabled "live heartbeat arbitrary_shell_enabled"
  Assert-False $apply.project_control_unpaused "live heartbeat project_control_unpaused"
  Assert-TokenPrintedFalse $apply

  $workersAfterApply = Invoke-WorkerTemplateRunnerJson "GET" "/v1/workers"
  $worker = @($workersAfterApply.workers | Where-Object { [string]$_.worker_id -eq $workerId })[0]
  if (-not $worker) { throw "Live heartbeat fixture worker was not registered." }
  if ([string]$worker.name -ne "Jerry Windows Local Worker") { throw "Live heartbeat fixture worker name mismatch." }
  if ([string]$worker.provider -ne "local-windows") { throw "Live heartbeat fixture worker provider mismatch." }
  if ([string]$worker.status -ne "online") { throw "Live heartbeat fixture worker should be online." }
  if ($worker.current_task_id) { throw "Live heartbeat fixture worker should not have a current task." }

  $tasks = Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  if (@($tasks.tasks).Count -ne 0) { throw "Live heartbeat fixture should not create or claim tasks." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-live-heartbeat-fixture"
    schema = $apply.schema
    worker_id = $apply.worker_id
    worker_registered = $apply.worker_registered
    heartbeat_sent = $apply.heartbeat_sent
    cloud_worker_status = $apply.cloud_worker_status
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
