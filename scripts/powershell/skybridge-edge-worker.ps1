[CmdletBinding(DefaultParameterSetName = "Once")]
param(
  [string]$ConfigFile = ".\config\edge-worker.example.json",
  [switch]$Register,
  [switch]$Heartbeat,
  [switch]$PollOnce,
  [switch]$Loop,
  [switch]$DryRun,
  [switch]$Send,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Write-EdgeWorkerResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 20
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

function Invoke-EdgeWorkerOnce {
  param($Config)

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
    $next = Get-NextTask -Config $Config
    if (-not $next.task) {
      $steps += @{ step = "poll"; status = "empty"; skipped = @($next.skipped) }
      return @{ ok = $true; worker_id = $Config.worker_id; dry_run = [bool]$DryRun; steps = $steps }
    }

    $claimPreview = @{
      task_id = $next.task.task_id
      title = $next.task.title
      task_type = $next.task_type
      skipped = @($next.skipped)
    }
    if ($DryRun) {
      $steps += @{ step = "claim"; status = "preview"; preview = $claimPreview }
      return @{ ok = $true; worker_id = $Config.worker_id; dry_run = $true; steps = $steps }
    }

    $claimed = Claim-Task -Config $Config -TaskId $next.task.task_id
    $steps += @{ step = "claim"; status = "claimed"; task = $claimed.task }
    Invoke-EdgeWorkerNotification -Config $Config -Severity "info" -Title "SkyBridge task claimed" -Message "Worker $($Config.worker_id) claimed $($next.task.task_id)." | Out-Null
  }

  return @{ ok = $true; worker_id = $Config.worker_id; dry_run = [bool]$DryRun; steps = $steps }
}

$config = Read-SkyBridgeWorkerConfig -ConfigFile $ConfigFile

if (-not ($Register -or $Heartbeat -or $PollOnce -or $Loop)) {
  $PollOnce = $true
}

Invoke-EdgeWorkerNotification -Config $config -Severity "info" -Title "SkyBridge edge worker started" -Message "Worker $($config.worker_id) started." | Out-Null

if ($Loop) {
  while ($true) {
    $result = Invoke-EdgeWorkerOnce -Config $config
    Write-EdgeWorkerResult -Result $result
    Start-Sleep -Seconds ([int]$config.poll_interval_seconds)
  }
} else {
  Write-EdgeWorkerResult -Result (Invoke-EdgeWorkerOnce -Config $config)
}
