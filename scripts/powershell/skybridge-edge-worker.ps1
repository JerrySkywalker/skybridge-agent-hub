[CmdletBinding(DefaultParameterSetName = "Once")]
param(
  [string]$ConfigFile = ".\config\edge-worker.example.json",
  [string]$WorkerProfileFile,
  [string]$ProjectId,
  [string]$TaskId,
  [switch]$Register,
  [switch]$Heartbeat,
  [switch]$PollOnce,
  [switch]$Loop,
  [int]$PollIntervalSeconds = 0,
  [int]$MaxTasks = 0,
  [int]$IdleTimeoutSeconds = 0,
  [switch]$StopOnFailure,
  [switch]$ClaimOnly,
  [switch]$DryRun,
  [switch]$Send,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$edgeConfigFile = $ConfigFile
$edgeWorkerProfileFile = $WorkerProfileFile
$edgeProjectId = $ProjectId
$edgeTaskId = $TaskId
$edgeJson = $Json

. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")
. (Join-Path $PSScriptRoot "load-worker-profile.ps1")
. (Join-Path $PSScriptRoot "invoke-codex-task.ps1")
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$ConfigFile = $edgeConfigFile
$WorkerProfileFile = $edgeWorkerProfileFile
$ProjectId = $edgeProjectId
$TaskId = $edgeTaskId
$Json = $edgeJson

function Write-EdgeWorkerResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 20 -Compress
  } else {
    $Result | Format-List
  }
}

function Invoke-EdgeWorkerNotification {
  param([string]$Severity, [string]$Title, [string]$Message, $Config)
  if (-not $Config.notification_enabled) { return @{ skipped = $true; reason = "notification_disabled" } }
  $scriptPath = Join-Path $PSScriptRoot "notify-bootstrap.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return @{ skipped = $true; reason = "notify_bootstrap_missing" } }
  $args = @("-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-Title", $Title, "-Message", $Message, "-Severity", $Severity, "-Json")
  if ($Send) { $args += "-Send" } else { $args += "-DryRun" }
  $output = & pwsh @args
  return ($output | ConvertFrom-Json)
}

function New-EdgeWorkerLoopLogDir {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $dir = Join-Path ".\.agent\edge-worker-loop" $timestamp
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return $dir
}

function Write-EdgeWorkerLoopLog {
  param([string]$LogDir, [string]$Event, [hashtable]$Data = @{})
  if ([string]::IsNullOrWhiteSpace($LogDir)) { return }
  $record = @{
    time = (Get-Date).ToUniversalTime().ToString("o")
    event = $Event
  }
  foreach ($key in $Data.Keys) { $record[$key] = $Data[$key] }
  Add-Content -LiteralPath (Join-Path $LogDir "loop.jsonl") -Value ($record | ConvertTo-Json -Depth 20 -Compress)
}

function Test-CommandAvailable {
  param([string]$Command)
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-GitHubAuthAvailable {
  try {
    & gh auth status 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Test-RepoClean {
  param($Config)
  try {
    $status = & git -C $Config.repo_path status --porcelain
    return [string]::IsNullOrWhiteSpace(($status -join "`n"))
  } catch {
    return $false
  }
}

function Resolve-CodexCommandForCheck {
  param($Config)
  if ($Config.codex_command) { return [string]$Config.codex_command }
  return "codex"
}

function Test-EdgeWorkerReadiness {
  param($Config)
  $issues = @()
  if (-not (Test-SkyBridgeServerAvailable -Config $Config)) { $issues += "skybridge_server_unavailable" }
  if (-not $DryRun) {
    if (-not (Test-CommandAvailable -Command (Resolve-CodexCommandForCheck -Config $Config))) { $issues += "codex_missing" }
    if (-not (Test-CommandAvailable -Command "gh")) { $issues += "github_cli_missing" }
    elseif (-not (Test-GitHubAuthAvailable)) { $issues += "github_auth_missing" }
    if (-not (Test-RepoClean -Config $Config)) { $issues += "repo_dirty" }
  }
  return @{
    ok = ($issues.Count -eq 0)
    issues = @($issues)
  }
}

function Start-SkyBridgeTaskKeepalive {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId)
  if ($DryRun) { return $null }
  $interval = if ($Config.lease_keepalive_interval_seconds) { [int]$Config.lease_keepalive_interval_seconds } else { 45 }
  if ($interval -lt 10) { $interval = 10 }
  $stopFile = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-keepalive-{0}-{1}.stop" -f $Config.worker_id, ([Guid]::NewGuid().ToString("n")))
  $helperPath = Join-Path $PSScriptRoot "skybridge-worker-api.ps1"
  $configJson = $Config | ConvertTo-Json -Depth 30 -Compress
  $job = Start-Job -ScriptBlock {
    param([string]$ConfigJson, [string]$HelperPath, [string]$StopFile, [int]$IntervalSeconds, [string]$ActiveTaskId)
    $ErrorActionPreference = "SilentlyContinue"
    . $HelperPath
    $workerConfig = $ConfigJson | ConvertFrom-Json
    while (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) {
      try { Send-WorkerHeartbeat -Config $workerConfig -StatusNote "task-active:$ActiveTaskId" -Load 1 | Out-Null } catch {}
      Start-Sleep -Seconds $IntervalSeconds
    }
  } -ArgumentList $configJson, $helperPath, $stopFile, $interval, $TaskId
  [pscustomobject]@{
    job = $job
    stop_file = $stopFile
    interval_seconds = $interval
    task_id = $TaskId
  }
}

function Stop-SkyBridgeTaskKeepalive {
  param($Keepalive, $Config, [Parameter(Mandatory = $true)][string]$TaskId)
  if (-not $Keepalive) { return $null }
  try { New-Item -ItemType File -Path $Keepalive.stop_file -Force | Out-Null } catch {}
  try { Wait-Job -Job $Keepalive.job -Timeout 5 | Out-Null } catch {}
  try {
    if ($Keepalive.job.State -eq "Running") { Stop-Job -Job $Keepalive.job | Out-Null }
    Remove-Job -Job $Keepalive.job -Force | Out-Null
  } catch {}
  try { Remove-Item -LiteralPath $Keepalive.stop_file -Force -ErrorAction SilentlyContinue } catch {}
  $heartbeat = $null
  try { $heartbeat = Send-WorkerHeartbeat -Config $Config -StatusNote "task-finished:$TaskId" -Load 0 } catch {}
  [pscustomobject]@{
    stopped = $true
    task_id = $TaskId
    post_task_heartbeat = [bool]$heartbeat
  }
}

function Invoke-EdgeWorkerOnce {
  param($Config, [string]$TargetTaskId)

  $steps = @()
  if ($Register) {
    if ($DryRun) {
      $steps += @{ step = "register"; dry_run = $true; worker_id = $Config.worker_id }
    } else {
      $steps += @{ step = "register"; response = Register-Worker -Config $Config }
    }
  }

  if ($Heartbeat -or $PollOnce) {
    if ($DryRun) {
      $steps += @{ step = "heartbeat"; dry_run = $true; worker_id = $Config.worker_id }
    } else {
      $steps += @{ step = "heartbeat"; response = Send-WorkerHeartbeat -Config $Config -StatusNote "polling" }
    }
  }

  if ($PollOnce) {
    $control = $null
    try { $control = (Get-ProjectControlState -Config $Config).control_state } catch {}
    if ($control) {
      $steps += @{ step = "control"; state = $control.state; stop_requested = [bool]$control.stop_requested }
      if ($control.stop_requested -or $control.state -eq "stopped") {
        return @{ ok = $true; worker_id = $Config.worker_id; dry_run = [bool]$DryRun; stop_reason = "control_stop_requested"; steps = $steps }
      }
      if ($control.state -eq "paused") {
        return @{ ok = $true; worker_id = $Config.worker_id; dry_run = [bool]$DryRun; stop_reason = "control_paused"; steps = $steps }
      }
    }

    $next = Get-NextTask -Config $Config -TaskId $TargetTaskId
    if (-not $next.task) {
      $steps += @{ step = "poll"; status = "empty"; skipped = @($next.skipped) }
      return @{ ok = $true; worker_id = $Config.worker_id; target_task_id = $TargetTaskId; dry_run = [bool]$DryRun; steps = $steps }
    }

    $claimPreview = @{
      task_id = $next.task.task_id
      title = $next.task.title
      task_type = $next.task_type
      skipped = @($next.skipped)
    }
    if ($DryRun) {
      $steps += @{ step = "claim"; status = "preview"; preview = $claimPreview }
      return @{ ok = $true; worker_id = $Config.worker_id; target_task_id = $TargetTaskId; dry_run = $true; steps = $steps }
    }

    $claimed = Claim-Task -Config $Config -TaskId $next.task.task_id
    $steps += @{ step = "claim"; status = "claimed"; task = $claimed.task }
    Invoke-EdgeWorkerNotification -Config $Config -Severity "info" -Title "SkyBridge task claimed" -Message "Worker $($Config.worker_id) claimed $($next.task.task_id)." | Out-Null
    if ($ClaimOnly) {
      $steps += @{ step = "execute"; status = "skipped"; reason = "claim_only" }
      return @{ ok = $true; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
    }

    $repoLock = $null
    $keepalive = $null
    try {
      $safety = Test-SkyBridgeWorkerTaskSafety -Config $Config -Task $claimed.task
      $steps += @{ step = "workspace_safety"; status = $(if ($safety.ok) { "passed" } else { "blocked" }); result = $safety }
      if (-not $safety.ok) {
        $blocked = Block-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = "Worker workspace safety guard blocked execution: $($safety.reason)"
          guard_reason = $safety.reason
          failed_guards = @($safety.failed_guards)
        }
        $steps += @{ step = "block"; task = $blocked.task; reason = $safety.reason }
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $repoLock = New-SkyBridgeRepoLock -Config $Config -Task $claimed.task
      $steps += @{ step = "repo_lock"; status = $(if ($repoLock.ok) { "acquired" } else { "blocked" }); lock = $repoLock }
      if (-not $repoLock.ok) {
        $blocked = Block-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = "Worker repo lock blocked execution: $($repoLock.error)"
          guard_reason = $repoLock.error
        }
        $steps += @{ step = "block"; task = $blocked.task; reason = $repoLock.error }
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $started = Start-Task -Config $Config -TaskId $next.task.task_id
      $steps += @{ step = "start"; status = "running"; task = $started.task }
      $steps += @{ step = "pre_task_heartbeat"; response = Send-WorkerHeartbeat -Config $Config -StatusNote "task-started:$($next.task.task_id)" }
      $keepalive = Start-SkyBridgeTaskKeepalive -Config $Config -TaskId $next.task.task_id
      if ($keepalive) { $steps += @{ step = "lease_keepalive"; status = "started"; interval_seconds = $keepalive.interval_seconds; stop_file = $keepalive.stop_file } }

      $maxTransportRetries = if ($null -ne $Config.codex_transport_max_retries) { [int]$Config.codex_transport_max_retries } else { 1 }
      if ($maxTransportRetries -lt 0) { $maxTransportRetries = 0 }
      $execution = $null
      $classification = $null
      $retryCount = 0
      for ($attempt = 0; $attempt -le $maxTransportRetries; $attempt++) {
        if ($attempt -gt 0) {
          Reset-CodexTaskWorkspace -Config $Config -Task $claimed.task | Out-Null
          $retryCount = $attempt
          $steps += @{ step = "execute_retry"; retry_count = $attempt; reason = $classification.execution_error_class }
        }
        $execution = Invoke-CodexTask -Config $Config -Task $claimed.task
        $classification = Get-CodexExecutionFailureClassification -ExecutionResult $execution
        if ($execution -and (Get-Member -InputObject $execution -Name execution_error_class -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
          $execution.execution_error_class = $classification.execution_error_class
        } else {
          $execution | Add-Member -NotePropertyName execution_error_class -NotePropertyValue $classification.execution_error_class -Force
        }
        if ($execution -and (Get-Member -InputObject $execution -Name retriable -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
          $execution.retriable = [bool]$classification.retriable
        } else {
          $execution | Add-Member -NotePropertyName retriable -NotePropertyValue ([bool]$classification.retriable) -Force
        }
        if ($execution -and (Get-Member -InputObject $execution -Name retry_count -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
          $execution.retry_count = $retryCount
        } else {
          $execution | Add-Member -NotePropertyName retry_count -NotePropertyValue $retryCount -Force
        }
        if ($execution.ok -or -not $classification.retriable -or $attempt -ge $maxTransportRetries) { break }
      }
      $steps += @{ step = "execute"; result = $execution; classification = $classification; retry_count = $retryCount }
      if (-not $execution.ok) {
        $summaryText = if ($classification.execution_error_class -in @("codex_transport_eof", "codex_transport_error")) {
          "Codex transport failed after $retryCount retry."
        } else {
          ($execution.error_summary ?? $execution.summary)
        }
        $failed = Fail-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = ($summaryText -replace "\s+", " ").Substring(0, [Math]::Min(240, ($summaryText -replace "\s+", " ").Length))
          result_url = $execution.last_message_path
          execution_error_class = $classification.execution_error_class
          retry_count = $retryCount
          recovered = $false
        }
        $steps += @{ step = "fail"; task = $failed.task }
        Invoke-EdgeWorkerNotification -Config $Config -Severity "urgent" -Title "SkyBridge task failed" -Message "Task $($next.task.task_id) failed during Codex execution." | Out-Null
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $validation = Invoke-TaskValidation -Config $Config -Task $claimed.task -ExecutionResult $execution
      $steps += @{ step = "validate"; result = $validation }
      if (-not $validation.ok) {
        $failed = Fail-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = "Validation failed. Local log: $($validation.log_path)"
          result_url = $execution.last_message_path
        }
        $steps += @{ step = "fail"; task = $failed.task }
        Invoke-EdgeWorkerNotification -Config $Config -Severity "urgent" -Title "SkyBridge task failed" -Message "Task $($next.task.task_id) failed validation." | Out-Null
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $pr = Invoke-GitPrIntegration -Config $Config -Task $claimed.task -ExecutionResult $execution -ValidationResult $validation
      $steps += @{ step = "pr"; result = $pr }
      if (-not $pr.ok) {
        $failed = Fail-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = $pr.summary
          result_url = $execution.last_message_path
        }
        $steps += @{ step = "fail"; task = $failed.task }
        Invoke-EdgeWorkerNotification -Config $Config -Severity "urgent" -Title "SkyBridge task failed" -Message "Task $($next.task.task_id) failed PR packaging." | Out-Null
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $ci = Invoke-CiGuardianForTask -Config $Config -Task $claimed.task -PRResult $pr
      $steps += @{ step = "ci_guardian"; result = $ci }
      if (-not $ci.ok) {
        $failed = Fail-Task -Config $Config -TaskId $next.task.task_id -Result @{
          error_summary = $ci.summary
          result_url = $execution.last_message_path
          pr_url = $pr.pr_url
        }
        $steps += @{ step = "fail"; task = $failed.task }
        Invoke-EdgeWorkerNotification -Config $Config -Severity "urgent" -Title "SkyBridge task blocked" -Message "Task $($next.task.task_id) needs CI review." | Out-Null
        return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
      }

      $complete = Complete-Task -Config $Config -TaskId $next.task.task_id -Result @{
        summary = "Edge worker completed task. Execution: $($execution.status). Validation: $($validation.status). PR: $($pr.status). CI: $($ci.status)."
        result_url = $execution.last_message_path
        pr_url = $pr.pr_url
      }
      $steps += @{ step = "complete"; task = $complete.task }
      Invoke-EdgeWorkerNotification -Config $Config -Severity "info" -Title "SkyBridge task completed" -Message "Task $($next.task.task_id) completed by $($Config.worker_id)." | Out-Null
    } catch {
      $failed = Fail-Task -Config $Config -TaskId $next.task.task_id -Result @{
        error_summary = ($_.Exception.Message -replace "\s+", " ").Substring(0, [Math]::Min(240, ($_.Exception.Message -replace "\s+", " ").Length))
      }
      $steps += @{ step = "fail"; task = $failed.task; error = $_.Exception.Message }
      Invoke-EdgeWorkerNotification -Config $Config -Severity "urgent" -Title "SkyBridge task failed" -Message "Task $($next.task.task_id) failed with an edge worker error." | Out-Null
      return @{ ok = $false; worker_id = $Config.worker_id; dry_run = $false; task_id = $next.task.task_id; steps = $steps }
    } finally {
      if ($keepalive) {
        $stoppedKeepalive = Stop-SkyBridgeTaskKeepalive -Keepalive $keepalive -Config $Config -TaskId $next.task.task_id
        $steps += @{ step = "lease_keepalive"; status = "stopped"; result = $stoppedKeepalive }
      }
      if ($repoLock -and $repoLock.ok) {
        Remove-SkyBridgeRepoLock -Lock $repoLock | Out-Null
      }
    }
  }

  return @{ ok = $true; worker_id = $Config.worker_id; target_task_id = $TargetTaskId; dry_run = [bool]$DryRun; steps = $steps }
}

function Test-NewWorkerProfileShape {
  param($Candidate)
  return (
    $Candidate -and
    -not [string]::IsNullOrWhiteSpace([string]$Candidate.worker_id) -and
    $Candidate.project_ids -and
    $Candidate.repo_paths -and
    -not [string]::IsNullOrWhiteSpace([string]$Candidate.skybridge_api_base)
  )
}

function Read-EdgeWorkerConfig {
  param([string]$Path, [string]$SelectedProjectId)
  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
  $raw = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  if (Test-NewWorkerProfileShape -Candidate $raw) {
    $profile = Read-WorkerProfile -Path $resolved.Path
    return ConvertTo-EdgeWorkerConfig -Profile $profile -ProjectId $SelectedProjectId
  }
  return Read-SkyBridgeWorkerConfig -ConfigFile $resolved.Path
}

if ($WorkerProfileFile -or $env:SKYBRIDGE_WORKER_PROFILE) {
  $profile = Read-WorkerProfile -Path $WorkerProfileFile
  $config = ConvertTo-EdgeWorkerConfig -Profile $profile -ProjectId $ProjectId
} else {
  $config = Read-EdgeWorkerConfig -Path $ConfigFile -SelectedProjectId $ProjectId
}
Assert-SkyBridgeWorkerApiSafety -Config $config
if ($PollIntervalSeconds -gt 0) { $config | Add-Member -NotePropertyName poll_interval_seconds -NotePropertyValue $PollIntervalSeconds -Force }

if (-not ($Register -or $Heartbeat -or $PollOnce -or $Loop)) {
  $PollOnce = $true
}

Invoke-EdgeWorkerNotification -Config $config -Severity "info" -Title "SkyBridge edge worker started" -Message "Worker $($config.worker_id) started." | Out-Null

if ($Loop) {
  $Register = $true
  $Heartbeat = $true
  $PollOnce = $true
  $logDir = New-EdgeWorkerLoopLogDir
  $completedTasks = 0
  $idleStartedAt = $null
  $stopReason = $null
  Write-EdgeWorkerLoopLog -LogDir $logDir -Event "loop_start" -Data @{
    worker_id = $config.worker_id
    project_id = $config.project_id
    max_tasks = $MaxTasks
    idle_timeout_seconds = $IdleTimeoutSeconds
    dry_run = [bool]$DryRun
  }

  try {
    if (-not $DryRun) {
      Set-ProjectControlState -Config $config -Patch @{
        state = "running"
        stop_requested = $false
        current_worker_id = $config.worker_id
        max_tasks = $(if ($MaxTasks -gt 0) { $MaxTasks } else { $null })
        degraded_reason = $null
        stop_reason = $null
      } | Out-Null
    }

    while ($true) {
      $readiness = Test-EdgeWorkerReadiness -Config $config
      if (-not $readiness.ok) {
        $reason = ($readiness.issues -join ",")
        Write-EdgeWorkerLoopLog -LogDir $logDir -Event "degraded" -Data @{ reason = $reason }
        if (Test-SkyBridgeServerAvailable -Config $config) {
          Set-ProjectControlState -Config $config -Patch @{
            state = "paused"
            degraded_reason = $reason
            last_error = $reason
            current_worker_id = $config.worker_id
            last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
          } | Out-Null
        }
        $stopReason = "degraded:$reason"
        break
      }

      $result = $null
      try {
        $result = Invoke-EdgeWorkerOnce -Config $config -TargetTaskId $TaskId
      } catch {
        $message = ($_.Exception.Message -replace "\s+", " ")
        Write-EdgeWorkerLoopLog -LogDir $logDir -Event "loop_error" -Data @{ error = $message }
        Set-ProjectControlState -Config $config -Patch @{
          state = "paused"
          last_error = $message.Substring(0, [Math]::Min(200, $message.Length))
          current_worker_id = $config.worker_id
          last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
        } | Out-Null
        if ($StopOnFailure) {
          $stopReason = "failure"
          break
        }
      }

      if ($result) {
        Write-EdgeWorkerResult -Result $result
        $stepNames = @($result.steps | ForEach-Object { $_.step })
        Write-EdgeWorkerLoopLog -LogDir $logDir -Event "iteration" -Data @{
          ok = [bool]$result.ok
          task_id = $result.task_id
          stop_reason = $result.stop_reason
          steps = @($stepNames)
        }
        if ($stepNames -contains "heartbeat") { Write-EdgeWorkerLoopLog -LogDir $logDir -Event "heartbeat" -Data @{ worker_id = $config.worker_id } }
        if ($stepNames -contains "poll") { Write-EdgeWorkerLoopLog -LogDir $logDir -Event "task_poll" -Data @{ task_id = $result.task_id } }
        if ($stepNames -contains "claim") { Write-EdgeWorkerLoopLog -LogDir $logDir -Event "task_claim" -Data @{ task_id = $result.task_id } }
        if ($stepNames -contains "complete") {
          $completedTasks++
          Write-EdgeWorkerLoopLog -LogDir $logDir -Event "task_complete" -Data @{ task_id = $result.task_id; completed_tasks = $completedTasks }
        }
        if ($stepNames -contains "fail") { Write-EdgeWorkerLoopLog -LogDir $logDir -Event "task_fail" -Data @{ task_id = $result.task_id } }

        $currentTaskId = if ($result.task_id) { $result.task_id } else { $null }
        Set-ProjectControlState -Config $config -Patch @{
          current_worker_id = $config.worker_id
          current_task_id = $currentTaskId
          loop_task_count = $completedTasks
          last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
          last_error = $(if ($result.ok) { $null } else { "last_task_failed" })
        } | Out-Null

        if ($result.stop_reason -eq "control_stop_requested" -or $result.stop_reason -eq "control_paused") {
          $stopReason = $result.stop_reason
          break
        }
        if (-not $result.ok -and $StopOnFailure) {
          $stopReason = "failure"
          break
        }
        if ($stepNames -contains "complete") {
          $idleStartedAt = $null
        } elseif ($stepNames -contains "poll" -and -not $idleStartedAt) {
          $idleStartedAt = Get-Date
        }
      }

      if ($MaxTasks -gt 0 -and $completedTasks -ge $MaxTasks) {
        $stopReason = "max_tasks"
        break
      }
      if ($IdleTimeoutSeconds -gt 0 -and $idleStartedAt) {
        if (((Get-Date) - $idleStartedAt).TotalSeconds -ge $IdleTimeoutSeconds) {
          $stopReason = "idle_timeout"
          break
        }
      }
      Start-Sleep -Seconds ([int]$config.poll_interval_seconds)
    }
  } finally {
    if (-not $stopReason) { $stopReason = "loop_ended" }
    Write-EdgeWorkerLoopLog -LogDir $logDir -Event "loop_stop" -Data @{ stop_reason = $stopReason; completed_tasks = $completedTasks }
    if (Test-SkyBridgeServerAvailable -Config $config) {
      try {
        Set-ProjectControlState -Config $config -Patch @{
          state = "paused"
          stop_requested = $false
          current_task_id = $null
          current_worker_id = $config.worker_id
          loop_task_count = $completedTasks
          stop_reason = $stopReason
          last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
        } | Out-Null
      } catch {}
    }
    Write-EdgeWorkerResult -Result @{
      ok = $true
      worker_id = $config.worker_id
      loop = $true
      log_dir = $logDir
      completed_tasks = $completedTasks
      stop_reason = $stopReason
      dry_run = [bool]$DryRun
    }
  }
} else {
  Write-EdgeWorkerResult -Result (Invoke-EdgeWorkerOnce -Config $config -TargetTaskId $TaskId)
}
