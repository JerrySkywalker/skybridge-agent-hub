[CmdletBinding()]
param(
  [string]$MasterGoalFile = ".\goals\master\self-bootstrap-smoke.md",
  [int]$MaxRounds = 3,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId = "self-bootstrap-smoke",
  [string]$WorkerConfigFile = ".\config\edge-worker.json",
  [switch]$DryRun,
  [switch]$Send,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-JsonScript {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function Invoke-LoopNotification {
  param([string]$Title, [string]$Message)
  $scriptPath = Join-Path $PSScriptRoot "notify-bootstrap.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return @{ skipped = $true; reason = "notify_bootstrap_missing" } }
  $args = @("-File", $scriptPath, "-Title", $Title, "-Message", $Message, "-Severity", "info", "-Json")
  if ($Send) { $args += "-Send" } else { $args += "-DryRun" }
  return Invoke-JsonScript -Arguments $args
}

$rounds = @()
$stopReason = $null
$loopRunDir = Join-Path ".\.agent\self-bootstrap" (Get-Date -Format "yyyyMMdd-HHmmss")
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $loopRunDir | Out-Null }

for ($round = 1; $round -le $MaxRounds; $round += 1) {
  $compactStateFile = $null
  if (-not $DryRun) {
    $compactStateFile = Join-Path $loopRunDir ("compact-state-round-{0}.json" -f $round)
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\build-planner-compact-state.ps1" `
      -ApiBase $ApiBase `
      -ProjectId $ProjectId `
      -GoalId $GoalId `
      -Json | Set-Content -LiteralPath $compactStateFile -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "failed to build planner compact state for round $round" }
  }

  $plannerArgs = @(
    "-File", ".\scripts\powershell\skybridge-hermes-planner.ps1",
    "-MasterGoalFile", $MasterGoalFile,
    "-ApiBase", $ApiBase,
    "-ProjectId", $ProjectId,
    "-GoalId", $GoalId,
    "-Json"
  )
  if ($compactStateFile) { $plannerArgs += @("-CompactStateFile", $compactStateFile) }
  if ($DryRun) { $plannerArgs += "-DryRun" } else { $plannerArgs += "-CreateTask" }

  try {
    $planner = Invoke-JsonScript -Arguments $plannerArgs
  } catch {
    $stopReason = "planner_unavailable: $($_.Exception.Message)"
    $rounds += [pscustomobject]@{ round = $round; status = "blocked"; reason = $stopReason }
    break
  }

  $decision = [string]$planner.decision.decision
  $roundRecord = [ordered]@{
    round = $round
    planner_decision = $decision
    planner_reason = [string]$planner.decision.reason
    task_id = $planner.task.task_id
    worker = $null
    evaluation = $null
    status = "planned"
  }

  if ($decision -in @("wait", "stop", "blocked")) {
    $roundRecord.status = $decision
    $stopReason = [string]$planner.decision.reason
    $rounds += [pscustomobject]$roundRecord
    break
  }

  if ($DryRun) {
    $roundRecord.task_id = "dry-run-round-$round"
    $roundRecord.worker = @{ dry_run = $true; status = "skipped" }
    $roundRecord.evaluation = @{ dry_run = $true; decision = @{ decision = if ($round -ge $MaxRounds) { "stop" } else { "continue" }; reason = "Dry-run loop evaluation." } }
    $roundRecord.status = "dry_run_completed"
    $rounds += [pscustomobject]$roundRecord
    continue
  }

  if (-not (Test-Path -LiteralPath $WorkerConfigFile -PathType Leaf)) {
    $roundRecord.status = "blocked"
    $roundRecord.worker = @{ status = "missing_config"; config = $WorkerConfigFile }
    $stopReason = "Worker config missing: $WorkerConfigFile"
    $rounds += [pscustomobject]$roundRecord
    break
  }

  $workerArgs = @("-File", ".\scripts\powershell\skybridge-edge-worker.ps1", "-ConfigFile", $WorkerConfigFile, "-PollOnce", "-Json")
  if ($Send) { $workerArgs += "-Send" }
  try {
    $worker = Invoke-JsonScript -Arguments $workerArgs
    $roundRecord.worker = $worker
  } catch {
    $roundRecord.status = "blocked"
    $roundRecord.worker = @{ status = "failed"; error = $_.Exception.Message }
    $stopReason = "worker_failed: $($_.Exception.Message)"
    $rounds += [pscustomobject]$roundRecord
    break
  }

  if ($planner.task.task_id) {
    try {
      $evaluation = Invoke-JsonScript -Arguments @(
        "-File", ".\scripts\powershell\skybridge-hermes-evaluate-result.ps1",
        "-TaskId", ([string]$planner.task.task_id),
        "-ApiBase", $ApiBase,
        "-GoalId", $GoalId,
        "-Json"
      )
      $roundRecord.evaluation = $evaluation
      $roundRecord.status = [string]$evaluation.decision.decision
      if ($evaluation.decision.decision -in @("wait", "stop", "blocked")) {
        $stopReason = [string]$evaluation.decision.reason
        $rounds += [pscustomobject]$roundRecord
        break
      }
    } catch {
      $roundRecord.status = "blocked"
      $roundRecord.evaluation = @{ status = "failed"; error = $_.Exception.Message }
      $stopReason = "evaluation_failed: $($_.Exception.Message)"
      $rounds += [pscustomobject]$roundRecord
      break
    }
  }

  $rounds += [pscustomobject]$roundRecord
}

$notification = $null
if ($Send -or $DryRun) {
  $notification = Invoke-LoopNotification -Title "SkyBridge self-bootstrap loop" -Message "Self-bootstrap loop finished $($rounds.Count) round(s). Status: $(if ($stopReason) { $stopReason } else { 'completed' })."
}

$result = [pscustomobject]@{
  ok = -not ($rounds | Where-Object { $_.status -eq "blocked" } | Select-Object -First 1)
  dry_run = [bool]$DryRun
  max_rounds = $MaxRounds
  rounds_completed = @($rounds | Where-Object { $_.status -in @("dry_run_completed", "continue", "stop") }).Count
  rounds = $rounds
  stop_reason = $stopReason
  notification = $notification
}

if ($Json) { $result | ConvertTo-Json -Depth 40 } else { $result | Format-List }
