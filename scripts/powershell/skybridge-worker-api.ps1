$ErrorActionPreference = "Stop"

function ConvertTo-SkyBridgeJson {
  param([Parameter(ValueFromPipeline = $true)]$InputObject)
  process {
    $InputObject | ConvertTo-Json -Depth 20
  }
}

function Read-SkyBridgeWorkerConfig {
  param([Parameter(Mandatory = $true)][string]$ConfigFile)

  $resolved = Resolve-Path -LiteralPath $ConfigFile -ErrorAction Stop
  $config = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($config.worker_id)) { throw "Worker config missing worker_id." }
  if ([string]::IsNullOrWhiteSpace($config.project_id)) { throw "Worker config missing project_id." }
  if ([string]::IsNullOrWhiteSpace($config.repo_path)) { throw "Worker config missing repo_path." }
  if ([string]::IsNullOrWhiteSpace($config.api_base)) { throw "Worker config missing api_base." }
  if ([string]::IsNullOrWhiteSpace($config.codex_sandbox)) { $config | Add-Member -NotePropertyName codex_sandbox -NotePropertyValue "workspace-write" -Force }
  if (-not $config.poll_interval_seconds) { $config | Add-Member -NotePropertyName poll_interval_seconds -NotePropertyValue 30 -Force }
  if (-not $config.max_task_runtime_minutes) { $config | Add-Member -NotePropertyName max_task_runtime_minutes -NotePropertyValue 30 -Force }
  if ($null -eq $config.auto_merge_enabled) { $config | Add-Member -NotePropertyName auto_merge_enabled -NotePropertyValue $false -Force }
  if ($null -eq $config.notification_enabled) { $config | Add-Member -NotePropertyName notification_enabled -NotePropertyValue $false -Force }
  return $config
}

function Invoke-SkyBridgeApi {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST", "PATCH", "DELETE")][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    $Body = $null,
    [Parameter(Mandatory = $true)][string]$ApiBase,
    [int]$TimeoutSeconds = 10
  )

  $uri = "$($ApiBase.TrimEnd('/'))$Path"
  try {
    if ($null -eq $Body) {
      if ($Method -in @("POST", "PATCH")) {
        return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" -TimeoutSec $TimeoutSeconds
      }
      return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec $TimeoutSeconds
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
  } catch {
    $message = $_.Exception.Message
    $responseText = $null
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = [System.IO.StreamReader]::new($stream)
        $responseText = $reader.ReadToEnd()
      }
    } catch {}
    if ($responseText) { $message = "$message $responseText" }
    throw "SkyBridge API $Method $Path failed: $message"
  }
}

function Register-Worker {
  param($Config)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/workers/register" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
    name = if ($Config.name) { $Config.name } else { $Config.worker_id }
    provider = "edge-worker"
    capabilities = @($Config.capabilities)
    labels = @("edge", "local", "windows")
    enabled = $true
  }
}

function Send-WorkerHeartbeat {
  param($Config, [string]$StatusNote = "ready", [double]$Load = 0)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($Config.worker_id))/heartbeat" -ApiBase $Config.api_base -Body @{
    status_note = $StatusNote
    load = $Load
    seen_at = (Get-Date).ToUniversalTime().ToString("o")
  }
}

function Get-QueuedTasks {
  param($Config)
  Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?status=queued&project_id=$([uri]::EscapeDataString($Config.project_id))" -ApiBase $Config.api_base
}

function Get-TaskType {
  param($Task)
  $text = @($Task.title, $Task.prompt_summary, $Task.body, (@($Task.required_capabilities) -join " ")) -join " "
  if ($text -match "(?i)\bdocs?\b|documentation|readme") { return "docs" }
  if ($text -match "(?i)\btest\b|typecheck|lint|validation") { return "test" }
  if ($text -match "(?i)\bdeploy|production|secret|credential|github settings\b") { return "blocked" }
  return "code"
}

function Test-TaskCompatible {
  param($Task, $Config)
  $workerCapabilities = @($Config.capabilities)
  $required = @($Task.required_capabilities)
  foreach ($capability in $required) {
    if ($workerCapabilities -notcontains $capability) {
      return @{ compatible = $false; reason = "missing_capability:$capability"; task_type = Get-TaskType -Task $Task }
    }
  }

  $taskType = Get-TaskType -Task $Task
  if (@($Config.blocked_task_types) -contains $taskType -or $taskType -eq "blocked") {
    return @{ compatible = $false; reason = "blocked_task_type:$taskType"; task_type = $taskType }
  }
  if (@($Config.allowed_task_types).Count -gt 0 -and @($Config.allowed_task_types) -notcontains $taskType) {
    return @{ compatible = $false; reason = "task_type_not_allowed:$taskType"; task_type = $taskType }
  }
  return @{ compatible = $true; reason = "compatible"; task_type = $taskType }
}

function Get-NextTask {
  param($Config)
  $response = Get-QueuedTasks -Config $Config
  $skipped = @()
  foreach ($task in @($response.tasks)) {
    $compatibility = Test-TaskCompatible -Task $task -Config $Config
    if ($compatibility.compatible) {
      return [pscustomobject]@{
        task = $task
        task_type = $compatibility.task_type
        skipped = $skipped
      }
    }
    $skipped += [pscustomobject]@{
      task_id = $task.task_id
      title = $task.title
      reason = $compatibility.reason
      task_type = $compatibility.task_type
    }
  }
  return [pscustomobject]@{ task = $null; task_type = $null; skipped = $skipped }
}

function Claim-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
  }
}

function Start-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
  }
}

function Complete-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{})
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -ApiBase $Config.api_base -Body $body
}

function Fail-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{})
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -ApiBase $Config.api_base -Body $body
}
