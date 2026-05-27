[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$TasksLimit = 12,
  [int]$WorkersLimit = 12,
  [switch]$ShowCompleted,
  [switch]$ShowAll,
  [string]$TaskId,
  [string]$WorkerId,
  [int]$TimeoutSeconds = 30,
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
  param($TimeValue)
  if ($null -eq $TimeValue -or [string]::IsNullOrWhiteSpace([string]$TimeValue)) { return "-" }
  try {
    $seen = $null
    if ($TimeValue -is [datetimeoffset]) {
      $seen = $TimeValue
    } elseif ($TimeValue -is [datetime]) {
      $dateTime = [datetime]$TimeValue
      if ($dateTime.Kind -eq [DateTimeKind]::Unspecified) {
        $dateTime = [datetime]::SpecifyKind($dateTime, [DateTimeKind]::Utc)
      }
      $seen = [datetimeoffset]$dateTime.ToUniversalTime()
    } else {
      $text = [string]$TimeValue
      if ($text -notmatch "(Z|[+-]\d{2}:?\d{2})$") {
        $dateTime = [datetime]::Parse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        $seen = [datetimeoffset]$dateTime.ToUniversalTime()
      } else {
        $seen = [datetimeoffset]::Parse($text)
      }
    }
    $age = [datetimeoffset]::UtcNow - $seen.ToUniversalTime()
    if ($age.TotalSeconds -lt 90) { return "$([int][Math]::Max(0, $age.TotalSeconds))s ago" }
    if ($age.TotalMinutes -lt 90) { return "$([int]$age.TotalMinutes)m ago" }
    if ($age.TotalHours -lt 48) { return "$([int]$age.TotalHours)h ago" }
    return "$([int]$age.TotalDays)d ago"
  } catch {
    return [string]$TimeValue
  }
}

function Select-TaskSummary {
  param($Task)
  $taskId = if ($Task.task_id) { [string]$Task.task_id } else { "-" }
  $result = $Task.result
  $evidenceSummary = if ($result -and $result.evidence_summary) { $result.evidence_summary } else { $null }
  $ciStatus = if ($evidenceSummary -and $evidenceSummary.ci_status) { [string]$evidenceSummary.ci_status } else { $null }
  $recovered = if ($evidenceSummary -and $evidenceSummary.recovered -eq $true) { $true } else { $false }
  $prUrl = if ($result -and $result.pr_url) { [string]$result.pr_url } elseif ($Task.pr_url) { [string]$Task.pr_url } else { $null }
  $rawStatus = if ($Task.status) { [string]$Task.status } else { "queued" }
  $displayStatus = $rawStatus
  if ($rawStatus -eq "failed" -and $recovered) {
    $displayStatus = if ($ciStatus -eq "passed_after_rerun") { "recovered" } else { "failed/recovered" }
  }
  [pscustomobject]@{
    task_id = $taskId
    status = $rawStatus
    raw_status = $rawStatus
    display_status = $displayStatus
    title = if ($Task.title) { [string]$Task.title } else { "-" }
    worker_id = if ($Task.assigned_worker_id) { [string]$Task.assigned_worker_id } else { "-" }
    updated_at = if ($Task.updated_at) { [string]$Task.updated_at } else { $null }
    pr_url = $prUrl
    result_url = if ($Task.result_url) { [string]$Task.result_url } else { $null }
    error_summary = if ($Task.error_summary) { [string]$Task.error_summary } else { $null }
    pr = if ($prUrl) { "pr" } else { "-" }
    evidence_summary = $evidenceSummary
    recovered = $recovered
    ci_status = $ciStatus
    summary = if ($result -and $result.summary) { [string]$result.summary } elseif ($Task.error_summary) { [string]$Task.error_summary } else { $null }
    evidence = if ($recovered) { "recovered" } elseif ($ciStatus) { $ciStatus } else { "-" }
  }
}

function Select-WorkerSummary {
  param($Worker)
  $seenAt = if ($Worker.last_seen_at) { $Worker.last_seen_at } else { $null }
  [pscustomobject]@{
    worker_id = if ($Worker.worker_id) { [string]$Worker.worker_id } else { "-" }
    status = if ($Worker.status) { [string]$Worker.status } else { "offline" }
    last_seen_at = if ($seenAt) { [string]$seenAt } else { $null }
    last_seen = if ($Worker.status -eq "online") { "0s ago" } else { Format-RelativeTime -TimeValue $seenAt }
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
    "  id                       status   seen         task"
    foreach ($worker in @($Status.workers | Sort-Object worker_id)) {
      "  $(Shorten-StatusText $worker.worker_id 24) $(Shorten-StatusText $worker.status 8) $(Shorten-StatusText $worker.last_seen 12) $(Shorten-StatusText $worker.current_task_id 24)"
    }
  }
  ""
  "Tasks:"
  if (@($Status.tasks).Count -eq 0) {
    "  -"
  } else {
    "  id                             status     worker             pr  evidence"
    foreach ($task in @($Status.tasks | Sort-Object task_id)) {
      "  $(Shorten-StatusText $task.task_id 30) $(Shorten-StatusText $task.display_status 10) $(Shorten-StatusText $task.worker_id 18) $(Shorten-StatusText $task.pr 3) $(Shorten-StatusText $task.evidence 18)"
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($TaskId) -and @($Status.tasks).Count -gt 0) {
    $task = @($Status.tasks)[0]
    ""
    "Task Detail:"
    "  task_id:        $($task.task_id)"
    "  raw_status:     $($task.raw_status)"
    "  display_status: $($task.display_status)"
    "  recovered:      $($task.recovered)"
    "  ci_status:      $(if ($task.ci_status) { $task.ci_status } else { '-' })"
    "  pr_url:         $(if ($task.pr_url) { $task.pr_url } else { '-' })"
    "  summary:        $(if ($task.summary) { $task.summary } else { '-' })"
  }
}

function Select-CompactRows {
  param(
    [array]$Rows,
    [int]$Limit
  )
  if ($Limit -lt 1) { return @() }
  return @($Rows | Select-Object -First $Limit)
}

function Select-VisibleTasks {
  param([array]$Tasks)
  if ($ShowAll -or $ShowCompleted -or -not [string]::IsNullOrWhiteSpace($TaskId)) { return @($Tasks) }
  return @($Tasks | Where-Object { $_.status -notin @("completed", "archived") })
}

$config = New-StatusApiConfig
if ($config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$health = Invoke-SkyBridgeApi -Method GET -Path "/v1/health" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
$project = $null
try { $project = Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds } catch {}
$control = $null
try { $control = (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).control_state } catch {}
$workers = (Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).workers
if (-not [string]::IsNullOrWhiteSpace($WorkerId)) {
  $workerResponse = Invoke-SkyBridgeApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $workers = @($workerResponse.worker)
}
$tasks = (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).tasks
if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
  $taskResponse = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $tasks = @($taskResponse.task)
}

$workerSummaries = @($workers | ForEach-Object { Select-WorkerSummary -Worker $_ })
$taskSummaries = @($tasks | ForEach-Object { Select-TaskSummary -Task $_ })

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
  workers = if ($Json) { $workerSummaries } else { Select-CompactRows -Rows $workerSummaries -Limit $WorkersLimit }
  tasks = if ($Json) { $taskSummaries } else { Select-CompactRows -Rows (Select-VisibleTasks -Tasks $taskSummaries) -Limit $TasksLimit }
  filters = [pscustomobject]@{
    tasks_limit = $TasksLimit
    workers_limit = $WorkersLimit
    show_completed = [bool]$ShowCompleted
    show_all = [bool]$ShowAll
    task_id = if ($TaskId) { $TaskId } else { $null }
    worker_id = if ($WorkerId) { $WorkerId } else { $null }
  }
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
