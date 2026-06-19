[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Invoke-Proof {
  param([string[]]$ExtraArgs, [switch]$AllowFailure)
  $raw = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-proof.ps1") @ExtraArgs -Json 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  if ($exitCode -ne 0 -and -not $AllowFailure) { throw "Heartbeat proof failed: $text" }
  $parsed = $text | ConvertFrom-Json
  [pscustomobject]@{
    exit_code = $exitCode
    result = $parsed
    text = $text
  }
}

function Assert-Contains {
  param($Values, [string]$Expected, [string]$Name)
  if (@($Values) -notcontains $Expected) { throw "$Name missing expected value '$Expected'." }
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-heartbeat-proof-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-heartbeat-proof.sqlite"
$configFile = Join-Path $tempDir "worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "SkyBridge Agent Hub"
  } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/skybridge-agent-hub/control" @{
    state = "paused"
    stop_requested = $false
    stop_reason = "operator_paused"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects/skybridge-agent-hub/goals" @{
    goal_id = "heartbeat-proof-smoke-goal"
    title = "Heartbeat proof smoke goal"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "heartbeat-proof-queued-task"
    project_id = "skybridge-agent-hub"
    goal_id = "heartbeat-proof-smoke-goal"
    title = "Queued task must remain unclaimed"
    risk = "low"
    source = "manual"
    required_capabilities = @("heartbeat")
  } | Out-Null

  @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local 01"
    project_id = "skybridge-agent-hub"
    repo_path = (Resolve-Path ".").Path
    api_base = $ApiBase
    capabilities = @("heartbeat")
    allowed_task_types = @()
    blocked_task_types = @("deploy", "production", "secrets")
    auto_merge_enabled = $false
    notification_enabled = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configFile -Encoding UTF8

  $missingFlag = Invoke-Proof -ExtraArgs @("-ConfigFile", $configFile) -AllowFailure
  if ($missingFlag.exit_code -eq 0) { throw "Missing -HeartbeatOnly flag must fail safely." }
  if ($missingFlag.result.ok -ne $false -or $missingFlag.result.error -ne "heartbeat_only_ack_required") {
    throw "Missing flag failure did not return the safe acknowledgement error."
  }
  Assert-False $missingFlag.result.token_printed "missing-flag token_printed"
  Assert-False $missingFlag.result.tasks_claimed "missing-flag tasks_claimed"
  Assert-False $missingFlag.result.codex_run_called "missing-flag codex_run_called"

  $beforeTasks = Invoke-SkyBridgeJson "GET" "/v1/tasks/summary"
  $beforeControl = Invoke-SkyBridgeJson "GET" "/v1/projects/skybridge-agent-hub/control"

  $proof = Invoke-Proof -ExtraArgs @("-ConfigFile", $configFile, "-HeartbeatOnly")
  $result = $proof.result
  if ($result.schema -ne "skybridge.worker_heartbeat_proof.v1") { throw "Unexpected proof schema." }
  Assert-True $result.ok "proof ok"
  Assert-True $result.heartbeat_sent "heartbeat_sent"
  Assert-True $result.worker_online_after "worker_online_after"
  if ($result.worker_id -ne "jerry-win-local-01") { throw "Unexpected worker id $($result.worker_id)." }
  Assert-Contains $result.online_worker_ids "jerry-win-local-01" "online_worker_ids"
  foreach ($flag in @(
    "tasks_claimed",
    "codex_run_called",
    "queue_apply_called",
    "campaign_metadata_advanced",
    "start_one_called",
    "run_until_hold_called",
    "project_control_unpaused",
    "token_printed"
  )) {
    Assert-False $result.$flag $flag
  }

  $afterTasks = Invoke-SkyBridgeJson "GET" "/v1/tasks/summary"
  $afterControl = Invoke-SkyBridgeJson "GET" "/v1/projects/skybridge-agent-hub/control"
  if ($beforeTasks.queued -ne 1 -or $afterTasks.queued -ne 1) { throw "Queued task count changed during heartbeat proof." }
  if ($afterTasks.claimed -ne 0 -or $afterTasks.running -ne 0) { throw "Heartbeat proof claimed or started work." }
  if ($beforeControl.control_state.state -ne "paused" -or $afterControl.control_state.state -ne "paused") {
    throw "Project control must remain paused."
  }

  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "deterministic-online"; name = "Deterministic Online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/deterministic-online/heartbeat" @{ seen_at = (Get-Date).ToUniversalTime().ToString("o"); status_note = "online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "deterministic-stale"; name = "Deterministic Stale" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/deterministic-stale/heartbeat" @{ seen_at = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString("o"); status_note = "stale" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "deterministic-offline"; name = "Deterministic Offline" } | Out-Null
  $workers = Invoke-SkyBridgeJson "GET" "/v1/workers"
  $online = @($workers.workers | Where-Object { $_.worker_id -eq "deterministic-online" })[0]
  $stale = @($workers.workers | Where-Object { $_.worker_id -eq "deterministic-stale" })[0]
  $offline = @($workers.workers | Where-Object { $_.worker_id -eq "deterministic-offline" })[0]
  if ($online.status -ne "online") { throw "Expected deterministic-online to be online." }
  if ($stale.status -ne "stale") { throw "Expected deterministic-stale to be stale." }
  if ($offline.status -ne "offline") { throw "Expected deterministic-offline to be offline." }

  $scriptText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-worker-heartbeat-proof.ps1")
  foreach ($forbidden in @("Claim-Task", "Start-Task", "Complete-Task", "Fail-Task", "Block-Task", "Get-NextTask", "Invoke-CodexTask", "skybridge-self-bootstrap-loop.ps1", "skybridge-dev-queue-control.ps1", "start-one", "run-until-hold")) {
    if ($scriptText -match [regex]::Escape($forbidden)) { throw "Heartbeat proof script references forbidden path: $forbidden" }
  }

  $summary = [pscustomobject]@{
    ok = $true
    smoke = "worker-heartbeat-proof"
    worker_id = $result.worker_id
    heartbeat_sent = $result.heartbeat_sent
    worker_online_after = $result.worker_online_after
    tasks_claimed = $false
    codex_run_called = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    project_control_state_after = $afterControl.control_state.state
    classification = [pscustomobject]@{
      online = $online.status
      stale = $stale.status
      offline = $offline.status
    }
    token_printed = $false
  }

  if ($Json) { $summary | ConvertTo-Json -Depth 20 -Compress }
  else { Complete-Smoke "worker-heartbeat-proof" }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
