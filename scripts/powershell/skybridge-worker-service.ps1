[CmdletBinding()]
param(
  [ValidateSet("status", "start-standby-preview", "start-standby", "heartbeat", "stop-preview", "stop", "readiness")]
  [string]$Command = "status",
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$WorkerProfile = "laptop-zenbookduo-standby",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$CurrentStepId = "dev-queue-189-200:super-196-campaign-locking-multi-campaign-queue",
  [string]$CurrentGoalId = "super-196-campaign-locking-multi-campaign-queue",
  [int]$MaxHeartbeats = 1,
  [int]$IntervalSeconds = 0,
  [switch]$Apply,
  [switch]$Json,
  [string]$Reason
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  return $root
}

function Get-ServiceDir {
  Join-Path (Get-RepoRoot) ".agent\tmp\worker-service"
}

function Get-StatePath {
  Join-Path (Get-ServiceDir) "worker-service-state.json"
}

function Get-LedgerPath {
  Join-Path (Get-ServiceDir) "worker-service-ledger.jsonl"
}

function New-CapabilityMatrix {
  [pscustomobject]@{
    heartbeat = $true
    status = $true
    stop = $true
    pause = $true
    task_claim = $false
    task_execute = $false
    codex_execute = $false
    pr_create = $false
    arbitrary_shell = $false
    token_printed = $false
  }
}

function New-WorkerServiceState {
  param(
    [ValidateSet("offline", "standby", "ready", "paused", "stopping", "error")]
    [string]$Mode = "offline",
    $HeartbeatAt = $null,
    $ServiceStartedAt = $null,
    [bool]$StopRequested = $false,
    [bool]$PauseRequested = $false,
    [bool]$TokenAvailable = $false
  )

  $blockers = New-Object System.Collections.Generic.List[string]
  if ($Mode -eq "offline") { $blockers.Add("worker_service_offline") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($HeartbeatAt)) { $blockers.Add("standby_heartbeat_required") | Out-Null }
  if ($StopRequested) { $blockers.Add("stop_requested") | Out-Null }
  if ($PauseRequested) { $blockers.Add("pause_requested") | Out-Null }
  if (-not $TokenAvailable) { $blockers.Add("worker_token_unavailable") | Out-Null }
  $blockers.Add("execution_disabled_until_goal_197") | Out-Null

  [pscustomobject]@{
    schema = "skybridge.worker_service_state.v1"
    worker_service_state = $true
    worker_id = $WorkerId
    worker_profile = $WorkerProfile
    mode = $Mode
    heartbeat_at = if ([string]::IsNullOrWhiteSpace([string]$HeartbeatAt)) { $null } else { [string]$HeartbeatAt }
    service_started_at = if ([string]::IsNullOrWhiteSpace([string]$ServiceStartedAt)) { $null } else { [string]$ServiceStartedAt }
    current_task_id = $null
    can_claim_tasks = $false
    can_execute_tasks = $false
    stop_requested = $StopRequested
    pause_requested = $PauseRequested
    capability_matrix = New-CapabilityMatrix
    readiness_blockers = @($blockers)
    token_available = $TokenAvailable
    token_printed = $false
  }
}

function Read-WorkerServiceState {
  $path = Get-StatePath
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    try { return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -ErrorAction Stop } catch {}
  }
  New-WorkerServiceState
}

function Write-WorkerServiceState {
  param($State)
  $dir = Get-ServiceDir
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $State | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
}

function Write-ServiceLedger {
  param([string]$EventType, $State)
  $dir = Get-ServiceDir
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $entry = [pscustomobject]@{
    schema = "skybridge.worker_service_ledger_event.v1"
    event_type = $EventType
    worker_id = $WorkerId
    mode = [string]$State.mode
    heartbeat_at = $State.heartbeat_at
    current_task_id = $null
    task_claimed = $false
    task_executed = $false
    codex_worker_execution_started = $false
    pr_created = $false
    arbitrary_shell_exposed = $false
    raw_logs_included = $false
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    token_printed = $false
  }
  ($entry | ConvertTo-Json -Depth 20 -Compress) | Add-Content -LiteralPath (Get-LedgerPath) -Encoding UTF8
}

function Test-TokenAvailable {
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN) -or
    -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE)
}

function Test-CleanWorktree {
  $status = (git status --short | Out-String).Trim()
  [string]::IsNullOrWhiteSpace($status)
}

function Get-RunnerLockStatus {
  $lock = Join-Path (Get-RepoRoot) ".agent\locks\skybridge-edge-worker.lock.json"
  if (Test-Path -LiteralPath $lock -PathType Leaf) { return "present" }
  "none"
}

function Get-WorkerReadiness {
  param($State)
  $blockers = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($State.readiness_blockers)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item) -and -not $blockers.Contains([string]$item)) {
      $blockers.Add([string]$item) | Out-Null
    }
  }
  $clean = Test-CleanWorktree
  $runnerLock = Get-RunnerLockStatus
  if (-not $clean) { $blockers.Add("worktree_dirty") | Out-Null }
  if ($runnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (-not [bool]$State.token_available -and -not $blockers.Contains("worker_token_unavailable")) { $blockers.Add("worker_token_unavailable") | Out-Null }
  if (-not $blockers.Contains("execution_disabled_until_goal_197")) { $blockers.Add("execution_disabled_until_goal_197") | Out-Null }

  $age = $null
  if (-not [string]::IsNullOrWhiteSpace([string]$State.heartbeat_at)) {
    $age = [int][Math]::Max(0, ((Get-Date).ToUniversalTime() - [datetime]::Parse([string]$State.heartbeat_at).ToUniversalTime()).TotalSeconds)
  }
  [pscustomobject]@{
    schema = "skybridge.worker_service_readiness.v1"
    worker_id = $WorkerId
    mode = [string]$State.mode
    heartbeat_age_seconds = $age
    ready_for_start_one_gate = $false
    clean_worktree = $clean
    known_campaign = ($CampaignId -eq "dev-queue-189-200" -and $CurrentGoalId -eq "super-196-campaign-locking-multi-campaign-queue")
    active_tasks = 0
    stale_leases = 0
    runner_lock_status = $runnerLock
    token_available = [bool]$State.token_available
    worker_profile_valid = -not [string]::IsNullOrWhiteSpace($WorkerProfile)
    can_claim_tasks = $false
    can_execute_tasks = $false
    blockers = @($blockers)
    warnings = @($(if ([string]$State.mode -eq "standby") { "standby_heartbeat_only_no_execution" }))
    recommended_action = if ([string]$State.mode -eq "offline") { "Start a bounded standby heartbeat; keep Start One disabled until a later reviewed gate." } else { "Monitor standby heartbeat; keep Start One disabled until a later reviewed gate." }
    token_printed = $false
  }
}

function New-ServiceEnvelope {
  param([string]$Mode, $State, $Readiness, [bool]$Mutates)
  [pscustomobject]@{
    ok = $true
    command = $Command
    mode = $Mode
    campaign_id = $CampaignId
    current_step_id = $CurrentStepId
    current_goal_id = $CurrentGoalId
    worker_service = $State
    readiness = $Readiness
    state_path = ".agent/tmp/worker-service/worker-service-state.json"
    ledger_path = ".agent/tmp/worker-service/worker-service-ledger.jsonl"
    mutates = $Mutates
    task_claimed = $false
    task_created = $false
    task_executed = $false
    codex_worker_execution_started = $false
    worker_loop_started = $false
    pr_created = $false
    external_notification_sent = $false
    arbitrary_shell_exposed = $false
    raw_logs_included = $false
    token_printed = $false
  }
}

function Write-Result {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 60 -Compress
    return
  }
  "Command: $($Result.command)"
  "Mode:    $($Result.mode)"
  "Worker:  $($Result.worker_service.worker_id)"
  "State:   $($Result.worker_service.mode)"
  "Claim:   false"
  "Execute: false"
  "TokenPrinted: false"
}

if ($MaxHeartbeats -lt 1) { $MaxHeartbeats = 1 }
if ($MaxHeartbeats -gt 5) { $MaxHeartbeats = 5 }
if ($IntervalSeconds -lt 0) { $IntervalSeconds = 0 }
if ($IntervalSeconds -gt 5) { $IntervalSeconds = 5 }

$state = Read-WorkerServiceState
$result = $null

switch ($Command) {
  "status" {
    $readiness = Get-WorkerReadiness -State $state
    $result = New-ServiceEnvelope -Mode "read" -State $state -Readiness $readiness -Mutates:$false
  }
  "readiness" {
    $readiness = Get-WorkerReadiness -State $state
    $result = New-ServiceEnvelope -Mode "read" -State $state -Readiness $readiness -Mutates:$false
  }
  "start-standby-preview" {
    $preview = New-WorkerServiceState -Mode "standby" -HeartbeatAt (Get-Date).ToUniversalTime().ToString("o") -ServiceStartedAt (Get-Date).ToUniversalTime().ToString("o") -TokenAvailable:(Test-TokenAvailable)
    $readiness = Get-WorkerReadiness -State $preview
    $result = New-ServiceEnvelope -Mode "preview" -State $preview -Readiness $readiness -Mutates:$false
  }
  "start-standby" {
    if (-not $Apply) {
      $preview = New-WorkerServiceState -Mode "standby" -HeartbeatAt (Get-Date).ToUniversalTime().ToString("o") -ServiceStartedAt (Get-Date).ToUniversalTime().ToString("o") -TokenAvailable:(Test-TokenAvailable)
      $readiness = Get-WorkerReadiness -State $preview
      $result = New-ServiceEnvelope -Mode "preview" -State $preview -Readiness $readiness -Mutates:$false
      break
    }
    $stopFile = Join-Path (Get-ServiceDir) "stop-requested.json"
    if (Test-Path -LiteralPath $stopFile -PathType Leaf) { Remove-Item -LiteralPath $stopFile -Force }
    $started = (Get-Date).ToUniversalTime().ToString("o")
    $state = New-WorkerServiceState -Mode "standby" -HeartbeatAt $started -ServiceStartedAt $started -TokenAvailable:(Test-TokenAvailable)
    for ($i = 0; $i -lt $MaxHeartbeats; $i++) {
      $state.heartbeat_at = (Get-Date).ToUniversalTime().ToString("o")
      $state.current_task_id = $null
      $state.can_claim_tasks = $false
      $state.can_execute_tasks = $false
      Write-WorkerServiceState -State $state
      Write-ServiceLedger -EventType "standby_heartbeat" -State $state
      if ($i -lt ($MaxHeartbeats - 1) -and $IntervalSeconds -gt 0) { Start-Sleep -Seconds $IntervalSeconds }
      if (Test-Path -LiteralPath $stopFile -PathType Leaf) {
        $state.stop_requested = $true
        $state.mode = "stopping"
        break
      }
    }
    Write-WorkerServiceState -State $state
    $readiness = Get-WorkerReadiness -State $state
    $result = New-ServiceEnvelope -Mode "apply" -State $state -Readiness $readiness -Mutates:$true
  }
  "heartbeat" {
    if (-not $Apply) {
      $preview = $state
      $preview.heartbeat_at = (Get-Date).ToUniversalTime().ToString("o")
      $readiness = Get-WorkerReadiness -State $preview
      $result = New-ServiceEnvelope -Mode "preview" -State $preview -Readiness $readiness -Mutates:$false
      break
    }
    $state.mode = if ([string]$state.mode -eq "offline") { "standby" } else { [string]$state.mode }
    $state.heartbeat_at = (Get-Date).ToUniversalTime().ToString("o")
    if ([string]::IsNullOrWhiteSpace([string]$state.service_started_at)) { $state.service_started_at = $state.heartbeat_at }
    $state.current_task_id = $null
    $state.can_claim_tasks = $false
    $state.can_execute_tasks = $false
    Write-WorkerServiceState -State $state
    Write-ServiceLedger -EventType "heartbeat" -State $state
    $readiness = Get-WorkerReadiness -State $state
    $result = New-ServiceEnvelope -Mode "apply" -State $state -Readiness $readiness -Mutates:$true
  }
  "stop-preview" {
    $preview = $state
    $preview.stop_requested = $true
    $preview.mode = "stopping"
    $readiness = Get-WorkerReadiness -State $preview
    $result = New-ServiceEnvelope -Mode "preview" -State $preview -Readiness $readiness -Mutates:$false
  }
  "stop" {
    if (-not $Apply) {
      $preview = $state
      $preview.stop_requested = $true
      $preview.mode = "stopping"
      $readiness = Get-WorkerReadiness -State $preview
      $result = New-ServiceEnvelope -Mode "preview" -State $preview -Readiness $readiness -Mutates:$false
      break
    }
    $dir = Get-ServiceDir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    ([pscustomobject]@{ stop_requested = $true; reason = $Reason; token_printed = $false } | ConvertTo-Json -Depth 10) |
      Set-Content -LiteralPath (Join-Path $dir "stop-requested.json") -Encoding UTF8
    $state.stop_requested = $true
    $state.mode = "stopping"
    $state.can_claim_tasks = $false
    $state.can_execute_tasks = $false
    Write-WorkerServiceState -State $state
    Write-ServiceLedger -EventType "stop_requested" -State $state
    $readiness = Get-WorkerReadiness -State $state
    $result = New-ServiceEnvelope -Mode "apply" -State $state -Readiness $readiness -Mutates:$true
  }
}

Write-Result -Result $result
