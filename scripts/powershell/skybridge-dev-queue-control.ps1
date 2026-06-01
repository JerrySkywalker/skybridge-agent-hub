[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("preflight", "watch", "start-one", "start-all", "safe-pause", "emergency-stop", "resume", "report", "unlock-stale-runner")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$GoalPackDir = "goals/dev-queue-189-200",
  [string]$WorkerProfile = "$HOME\.skybridge\worker.laptop-zenbookduo.json",
  [string]$HermesEnvFile = "$HOME\.skybridge\hermes.env.ps1",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$TokenEnvVar,
  [int]$MaxRuntimeMinutes = 240,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason,
  [ValidateSet("Auto", "Always", "Never")]
  [string]$ColorMode = "Auto",
  [switch]$Once,
  [switch]$NoClear,
  [switch]$Compact
)

$ErrorActionPreference = "Stop"

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  return ($output | ConvertFrom-Json)
}

function Invoke-TextScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  return ($output -join "`n")
}

function Get-TokenArgs {
  $args = @()
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  return $args
}

function Test-GitPreflight {
  $branch = (git branch --show-current).Trim()
  $dirty = -not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim())
  $mainSync = "unknown"
  try {
    git fetch origin main | Out-Null
    $mainSync = ((git rev-parse main).Trim() -eq (git rev-parse origin/main).Trim())
  } catch {
    $mainSync = "unknown"
  }
  [pscustomobject]@{ branch = $branch; dirty = $dirty; main_sync = $mainSync }
}

function Write-ControlOutput {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 80 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $ProjectId"
  "Campaign:     $CampaignId"
  "OK:           $($Result.ok)"
  if ($Result.summary) { $Result.summary }
  if ($Result.instructions) { $Result.instructions }
}

function Invoke-Preflight {
  $tokenArgs = Get-TokenArgs
  $git = Test-GitPreflight
  $active = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-ActiveOnly", "-Json", "-ColorMode", "Never"))
  $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
  $campaign = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $runner = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $worker = $null
  if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
    $worker = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-Json")
  }
  $goal189 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
  $checks = [ordered]@{
    git_clean = -not [bool]$git.dirty
    active_tasks_zero = ([int]$active.task_summary.active -eq 0)
    stale_leases_zero = ([int]$hygiene.task_summary.stale_leases -eq 0)
    runner_lock_clear = ([string]$runner.runner_lock_status -in @("none", "released"))
    campaign_exists = ($null -ne $campaign.campaign)
    goal_189_ready = ($goal189 -and [string]$goal189.status -eq "ready")
    project_paused = ([string]$active.control.state -eq "paused")
  }
  [pscustomobject]@{
    ok = -not (@($checks.GetEnumerator() | Where-Object { -not $_.Value }).Count -gt 0)
    command = "preflight"
    mode = "read"
    token_printed = $false
    git = $git
    checks = $checks
    active_tasks = [int]$active.task_summary.active
    stale_leases = [int]$hygiene.task_summary.stale_leases
    runner_lock_status = [string]$runner.runner_lock_status
    campaign_status = [string]$campaign.campaign.status
    current_step = [string]$campaign.campaign.current_step_id
    worker_status = if ($worker) { [string]$worker.remote_status } else { "unknown" }
    worker_current_task_id = if ($worker) { $worker.current_task_id } else { $null }
    summary = "preflight active=$($active.task_summary.active) stale_leases=$($hygiene.task_summary.stale_leases) runner_lock=$($runner.runner_lock_status) current=$($campaign.campaign.current_step_id)"
  }
}

if ($Apply -and $DryRun) { throw "Use either -Apply or -DryRun, not both." }
$mode = if ($Apply) { "apply" } else { "dry-run" }
$tokenArgs = Get-TokenArgs
$result = $null

switch ($Command) {
  "preflight" {
    $result = Invoke-Preflight
  }
  "watch" {
    $watchArgs = @("-File", ".\scripts\powershell\skybridge-campaign-watch.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-CampaignId", $CampaignId, "-ColorMode", $ColorMode) + $tokenArgs
    if ($Once) { $watchArgs += "-Once" }
    if ($NoClear) { $watchArgs += "-NoClear" }
    if ($Compact) { $watchArgs += "-Compact" }
    if ($Json) { $watchArgs += "-Json" }
    if ($OutputFile) { $watchArgs += @("-OutputFile", $OutputFile) }
    if ($Json) { $result = Invoke-JsonScript $watchArgs } else { Invoke-TextScript $watchArgs; return }
  }
  "start-one" {
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "1", "-MaxTasks", "1", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $result = Invoke-JsonScript $args
  }
  "start-all" {
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $result = Invoke-JsonScript $args
  }
  "safe-pause" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "safe-pause requires -Reason." }
    if (-not $Apply) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; token_printed = $false; would_pause_project = $true; would_hold_runner = $true; reason = $Reason }
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $hold = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-hold", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Apply", "-Json"))
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; runner = $hold; reason = $Reason }
    }
  }
  "emergency-stop" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "emergency-stop requires -Reason." }
    if (-not $Apply) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; token_printed = $false; would_stop_project = $true; reason = $Reason; instructions = "Dry-run only. With -Apply, press Ctrl+C in the runner window if it is still running." }
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "stop", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; reason = $Reason; instructions = "Press Ctrl+C in the runner window if it is still running." }
    }
  }
  "resume" {
    if (-not $Apply) { throw "resume requires -Apply." }
    Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json")) | Out-Null
    if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
      Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "register-heartbeat", "-ConfigFile", $WorkerProfile, "-Json") | Out-Null
    }
    $result = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "resume", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-MaxSteps", "12", "-MaxTasks", "12", "-StopOnFailure", "-AllowAutoMerge", "-AllowEvidenceRepair", "-HumanApproved", "-HumanApprovalReason", "Operator resumed bounded dev queue execution.", "-Apply", "-Json") + $tokenArgs)
  }
  "report" {
    $report = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-report", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; token_printed = $false; report = $report.report; hygiene_summary = $hygiene.hygiene_summary; active_tasks = $hygiene.task_summary.active; stale_leases = $hygiene.task_summary.stale_leases }
  }
  "unlock-stale-runner" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "unlock-stale-runner requires -Reason." }
    $status = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    if ([string]$status.runner_lock_status -eq "active") { throw "Refusing to unlock active non-stale runner lock." }
    if ([string]$status.runner_lock_status -notin @("stale", "released", "none")) { throw "Unsupported runner lock status: $($status.runner_lock_status)" }
    $unlockArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-unlock", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Json")
    if ($Apply) { $unlockArgs += "-Apply" } else { $unlockArgs += "-DryRun" }
    $result = Invoke-JsonScript $unlockArgs
  }
}

if (-not $result.PSObject.Properties["command"]) {
  $result | Add-Member -NotePropertyName command -NotePropertyValue $Command
}
if (-not $result.PSObject.Properties["mode"]) {
  $result | Add-Member -NotePropertyName mode -NotePropertyValue $mode
}
if (-not $result.PSObject.Properties["token_printed"]) {
  $result | Add-Member -NotePropertyName token_printed -NotePropertyValue $false
}
Write-ControlOutput $result
