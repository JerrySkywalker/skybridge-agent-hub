[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-StatusApiConfig {
  $authMode = "none"
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar) -or -not [string]::IsNullOrWhiteSpace($TokenFile)) {
    $authMode = "bearer_token"
  }
  [pscustomobject]@{
    api_base = $ApiBase
    project_id = $ProjectId
    auth_mode = $authMode
    token_env_var = $TokenEnvVar
    token_file = $TokenFile
  }
}

function Shorten-StatusText {
  param([string]$Value, [int]$Width)
  if ([string]::IsNullOrWhiteSpace($Value)) { $Value = "-" }
  if ($Value.Length -le $Width) { return $Value.PadRight($Width) }
  if ($Width -le 1) { return $Value.Substring(0, $Width) }
  return ($Value.Substring(0, $Width - 1) + "~")
}

function Format-RelativeTime {
  param([string]$IsoTime)
  if ([string]::IsNullOrWhiteSpace($IsoTime)) { return "-" }
  try {
    $seen = [datetimeoffset]::Parse($IsoTime)
    $age = [datetimeoffset]::UtcNow - $seen.ToUniversalTime()
    if ($age.TotalSeconds -lt 90) { return "$([int][Math]::Max(0, $age.TotalSeconds))s ago" }
    if ($age.TotalMinutes -lt 90) { return "$([int]$age.TotalMinutes)m ago" }
    if ($age.TotalHours -lt 48) { return "$([int]$age.TotalHours)h ago" }
    return "$([int]$age.TotalDays)d ago"
  } catch {
    return $IsoTime
  }
}

function Select-TaskSummary {
  param($Task)
  $taskId = if ($Task.task_id) { [string]$Task.task_id } else { "-" }
  [pscustomobject]@{
    task_id = $taskId
    status = if ($Task.status) { [string]$Task.status } else { "queued" }
    title = if ($Task.title) { [string]$Task.title } else { "-" }
    worker_id = if ($Task.assigned_worker_id) { [string]$Task.assigned_worker_id } else { "-" }
    updated_at = if ($Task.updated_at) { [string]$Task.updated_at } else { $null }
    pr_url = if ($Task.pr_url) { [string]$Task.pr_url } else { $null }
    result_url = if ($Task.result_url) { [string]$Task.result_url } else { $null }
    error_summary = if ($Task.error_summary) { [string]$Task.error_summary } else { $null }
    evidence_summary = $Task.evidence_summary
  }
}

function Select-WorkerSummary {
  param($Worker)
  [pscustomobject]@{
    worker_id = if ($Worker.worker_id) { [string]$Worker.worker_id } else { "-" }
    status = if ($Worker.status) { [string]$Worker.status } else { "offline" }
    last_seen_at = if ($Worker.last_seen_at) { [string]$Worker.last_seen_at } else { $null }
    last_seen = Format-RelativeTime -IsoTime $Worker.last_seen_at
    current_task_id = if ($Worker.current_task_id) { [string]$Worker.current_task_id } else { $null }
    auth_mode = if ($Worker.auth_mode) { [string]$Worker.auth_mode } else { $null }
    api_base = if ($Worker.api_base) { [string]$Worker.api_base } else { $null }
  }
}

function Write-CompactStatus {
  param($Status)
  "SkyBridge: $($Status.api_base)"
  "Health:    $($Status.health.status)"
  "Project:   $($Status.project_id)"
  "Control:   $($Status.control.state) stop=$($Status.control.stop_requested)"
  if ($Status.control.stop_reason) { "Stop:      $($Status.control.stop_reason)" }
  if ($Status.control.degraded_reason) { "Degraded:  $($Status.control.degraded_reason)" }
  ""
  "Workers:"
  if (@($Status.workers).Count -eq 0) {
    "  -"
  } else {
    foreach ($worker in @($Status.workers | Sort-Object worker_id)) {
      "  $(Shorten-StatusText $worker.worker_id 24) $(Shorten-StatusText $worker.status 8) $(Shorten-StatusText $worker.last_seen 12)"
    }
  }
  ""
  "Tasks:"
  if (@($Status.tasks).Count -eq 0) {
    "  -"
  } else {
    foreach ($task in @($Status.tasks | Sort-Object task_id)) {
      "  $(Shorten-StatusText $task.task_id 30) $(Shorten-StatusText $task.status 10) $(Shorten-StatusText $task.worker_id 20)"
    }
  }
}

$config = New-StatusApiConfig
if ($config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$health = Invoke-SkyBridgeApi -Method GET -Path "/v1/health" -ApiBase $ApiBase -Config $config -TimeoutSeconds 10
$project = $null
try { $project = Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds 10 } catch {}
$control = $null
try { $control = (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Config $config -TimeoutSeconds 10).control_state } catch {}
$workers = (Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $ApiBase -Config $config -TimeoutSeconds 10).workers
$tasks = (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds 10).tasks

$status = [pscustomobject]@{
  ok = $true
  api_base = $ApiBase
  project_id = $ProjectId
  token_printed = $false
  health = [pscustomobject]@{
    ok = [bool]$health.ok
    status = if ($health.ok) { "ok" } else { "unknown" }
    persistence = $health.persistence
  }
  project = $project.project
  control = if ($control) { $control } else { [pscustomobject]@{ state = "unknown"; stop_requested = $false } }
  workers = @($workers | ForEach-Object { Select-WorkerSummary -Worker $_ })
  tasks = @($tasks | ForEach-Object { Select-TaskSummary -Task $_ })
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
  $outputDir = Split-Path -Parent $OutputFile
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }
  $status | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $status | ConvertTo-Json -Depth 30 -Compress
} else {
  Write-CompactStatus -Status $status
}
