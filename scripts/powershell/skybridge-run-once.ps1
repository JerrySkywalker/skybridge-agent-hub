[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$WorkerProfile,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$TaskId,
  [string]$TaskTitle,
  [string]$TaskBody,
  [string]$TaskBodyFile,
  [string]$GoalId,
  [string]$GoalTitle,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp",
  [switch]$NoSubmit,
  [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

function Invoke-RunOnceJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function Test-GitClean {
  $status = git status --short
  return [string]::IsNullOrWhiteSpace(($status -join "`n"))
}

function Write-RunOnceResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 40 -Compress
    return
  }
  "Mode:       $($Result.mode)"
  "Project:    $ProjectId"
  if ($Result.task_id) { "Task:       $($Result.task_id)" }
  "Submitted:  $($Result.submitted)"
  "Started:    $($Result.project_started)"
  "Worker:     $($Result.worker_checked)"
  "PollOnce:   $($Result.poll_once)"
  "Paused:     $($Result.project_paused)"
  "Snapshots:  $($Result.output_dir)"
  "TokenPrinted: false"
}

$effectiveDryRun = $DryRun -or -not $Apply
if (-not $effectiveDryRun -and -not $AllowDirty -and -not (Test-GitClean)) {
  throw "Working tree is dirty. Commit/stash changes or pass -AllowDirty explicitly."
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$beforeFile = Join-Path $OutputDir "skybridge-run-once-before.json"
$afterFile = Join-Path $OutputDir "skybridge-run-once-after.json"
$submitFile = Join-Path $OutputDir "skybridge-run-once-submit.json"

$commonStatusArgs = @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
if ($TokenEnvVar) { $commonStatusArgs += @("-TokenEnvVar", $TokenEnvVar) }
if ($TokenFile) { $commonStatusArgs += @("-TokenFile", $TokenFile) }

$statusBefore = Invoke-RunOnceJson -Arguments ($commonStatusArgs + @("-OutputFile", $beforeFile))
$submit = $null
$submitted = "skipped"
$projectStarted = "skipped"
$workerChecked = "skipped"
$pollOnce = "skipped"
$projectPaused = "skipped"

try {
  if (-not $NoSubmit) {
    $submitArgs = @(
      "-File", ".\scripts\powershell\skybridge-submit.ps1",
      "-ApiBase", $ApiBase,
      "-ProjectId", $ProjectId,
      "-EnsureProject",
      "-EnsureGoal",
      "-Json",
      "-OutputFile", $submitFile
    )
    if ($GoalId) { $submitArgs += @("-GoalId", $GoalId) }
    if ($GoalTitle) { $submitArgs += @("-GoalTitle", $GoalTitle) }
    if ($TaskId) { $submitArgs += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $submitArgs += @("-TaskTitle", $TaskTitle) }
    if ($TaskBody) { $submitArgs += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $submitArgs += @("-TaskBodyFile", $TaskBodyFile) }
    if ($TokenEnvVar) { $submitArgs += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $submitArgs += @("-TokenFile", $TokenFile) }
    if ($effectiveDryRun) { $submitArgs += "-DryRun" } else { $submitArgs += "-Apply" }
    $submit = Invoke-RunOnceJson -Arguments $submitArgs
    $submitted = $submit.task.action
    if (-not $TaskId) { $TaskId = $submit.task.id }
  }

  if (-not $effectiveDryRun) {
    $controlArgs = @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "start", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MaxTasks", "1", "-Json")
    if ($TokenEnvVar) { $controlArgs += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $controlArgs += @("-TokenFile", $TokenFile) }
    Invoke-RunOnceJson -Arguments $controlArgs | Out-Null
    $projectStarted = "started"

    if ([string]::IsNullOrWhiteSpace($WorkerProfile)) { throw "skybridge-run-once -Apply requires -WorkerProfile." }
    $workerArgs = @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "register-heartbeat", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-Json")
    Invoke-RunOnceJson -Arguments $workerArgs | Out-Null
    $workerChecked = "register-heartbeat"

    $edgeArgs = @("-File", ".\scripts\powershell\skybridge-edge-worker.ps1", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-PollOnce", "-Json")
    Invoke-RunOnceJson -Arguments $edgeArgs | Out-Null
    $pollOnce = "completed"
  } else {
    $projectStarted = "would_start"
    $workerChecked = if ($WorkerProfile) { "would_register_heartbeat" } else { "skipped_no_worker_profile" }
    $pollOnce = "would_poll_once"
  }
} finally {
  if (-not $effectiveDryRun) {
    try {
      $pauseArgs = @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
      if ($TokenEnvVar) { $pauseArgs += @("-TokenEnvVar", $TokenEnvVar) }
      if ($TokenFile) { $pauseArgs += @("-TokenFile", $TokenFile) }
      Invoke-RunOnceJson -Arguments $pauseArgs | Out-Null
      $projectPaused = "paused"
    } catch {
      $projectPaused = "pause_failed"
    }
  } else {
    $projectPaused = "would_pause"
  }
}

$statusAfter = Invoke-RunOnceJson -Arguments ($commonStatusArgs + @("-OutputFile", $afterFile))

Write-RunOnceResult ([pscustomobject]@{
  ok = $true
  mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
  api_base = $ApiBase
  project_id = $ProjectId
  task_id = $TaskId
  token_printed = $false
  submitted = $submitted
  submit = $submit
  project_started = $projectStarted
  worker_checked = $workerChecked
  poll_once = $pollOnce
  project_paused = $projectPaused
  output_dir = $OutputDir
  snapshots = [pscustomobject]@{
    before = $beforeFile
    after = $afterFile
    submit = if (Test-Path -LiteralPath $submitFile -PathType Leaf) { $submitFile } else { $null }
  }
  status_before = $statusBefore
  status_after = $statusAfter
})
