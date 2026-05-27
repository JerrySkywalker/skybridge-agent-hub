[CmdletBinding()]
param(
  [ValidateSet("status", "submit-preview", "submit-apply", "run-once-preview", "run-once-apply", "inspect-task", "inspect-worker", "pause", "start")]
  [string]$Mode = "status",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$WorkerProfile,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$GoalId,
  [string]$GoalTitle,
  [string]$TaskId,
  [string]$TaskTitle,
  [string]$TaskBody,
  [string]$TaskBodyFile,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp"
)

$ErrorActionPreference = "Stop"

function Add-CommonAuthArgs {
  param([string[]]$Arguments)
  $result = @($Arguments)
  if ($TokenEnvVar) { $result += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $result += @("-TokenFile", $TokenFile) }
  return $result
}

function Invoke-GuideJsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function New-GuideNextCommand {
  param([string]$NextMode)
  $parts = @(
    "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1",
    "-Mode $NextMode",
    "-ApiBase `"$ApiBase`"",
    "-ProjectId `"$ProjectId`""
  )
  if ($GoalId) { $parts += "-GoalId `"$GoalId`"" }
  if ($TaskId) { $parts += "-TaskId `"$TaskId`"" }
  if ($WorkerProfile) { $parts += "-WorkerProfile `"$WorkerProfile`"" }
  elseif ($NextMode -like "run-once*") { $parts += "-WorkerProfile `"`$HOME\.skybridge\worker.<hostname>.json`"" }
  if ($TokenFile) { $parts += "-TokenFile `"$TokenFile`"" }
  elseif ($TokenEnvVar) { $parts += "-TokenEnvVar `"$TokenEnvVar`"" }
  else { $parts += "# add -TokenFile or -TokenEnvVar for remote auth" }
  return ($parts -join " ")
}

function Write-GuideResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 50 -Compress
    return
  }
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.goal_id) { "Goal:         $($Result.goal_id)" }
  if ($Result.task_id) { "Task:         $($Result.task_id)" }
  "Action:       $($Result.action)"
  "TokenPrinted: false"
  if ($Result.next_command) { "Next:         $($Result.next_command)" }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$result = $null

switch ($Mode) {
  "status" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status"; api_base = $ApiBase; project_id = $ProjectId; task_id = $TaskId; goal_id = $GoalId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "submit-preview"; status = $payload }
  }
  "submit-preview" {
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { throw "submit-preview requires -TaskTitle." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-EnsureProject", "-EnsureGoal", "-DryRun", "-Json")
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    $args += @("-TaskTitle", $TaskTitle)
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "dry-run-submit"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $payload.goal.id; task_id = $payload.task.id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "submit-apply"; submit = $payload }
  }
  "submit-apply" {
    if (-not $Apply) { throw "submit-apply requires explicit -Apply." }
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { throw "submit-apply requires -TaskTitle." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-EnsureProject", "-EnsureGoal", "-Apply", "-Json")
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    $args += @("-TaskTitle", $TaskTitle)
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "applied-submit"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $payload.goal.id; task_id = $payload.task.id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; submit = $payload }
  }
  "run-once-preview" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-DryRun", "-Json", "-OutputDir", $OutputDir)
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { $args += "-NoSubmit" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "dry-run-once"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $payload.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-apply"; run_once = $payload }
  }
  "run-once-apply" {
    if (-not $Apply) { throw "run-once-apply requires explicit -Apply." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Apply", "-Json", "-OutputDir", $OutputDir)
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) } else { $args += "-NoSubmit" }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "applied-run-once"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $payload.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "inspect-task"; run_once = $payload }
  }
  "inspect-task" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "inspect-task requires -TaskId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TaskId", $TaskId, "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "inspect-task"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; status = $payload }
  }
  "inspect-worker" {
    if ([string]::IsNullOrWhiteSpace($WorkerProfile)) { throw "inspect-worker requires -WorkerProfile." }
    $payload = Invoke-GuideJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-Json")
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "inspect-worker"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; worker = $payload }
  }
  "pause" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "pause"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; control = $payload }
  }
  "start" {
    if (-not $Apply) { throw "start requires explicit -Apply." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "start", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MaxTasks", "1", "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "start"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; control = $payload }
  }
}

Write-GuideResult -Result $result
