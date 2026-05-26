[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "start", "pause", "stop", "set-max-tasks")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$MaxTasks = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-ControlApiConfig {
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

function Invoke-ControlApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 10
}

function Get-ProjectControl {
  Invoke-ControlApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control"
}

function Set-ProjectControl {
  param([hashtable]$Patch)
  Invoke-ControlApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -Body $Patch
}

function Write-ControlResult {
  param($Result)
  $output = [pscustomobject]@{
    ok = $true
    api_base = $ApiBase
    project_id = $ProjectId
    command = $Command
    token_printed = $false
    control = $Result.control_state
  }
  if ($Json) {
    $output | ConvertTo-Json -Depth 20 -Compress
    return
  }
  "Project: $ProjectId"
  "API:     $ApiBase"
  "State:   $($output.control.state)"
  "Stop:    $($output.control.stop_requested)"
  if ($output.control.max_tasks) { "MaxTasks: $($output.control.max_tasks)" }
  if ($output.control.loop_task_count -ne $null) { "LoopTasks: $($output.control.loop_task_count)" }
  if ($output.control.current_worker_id) { "Worker:  $($output.control.current_worker_id)" }
  if ($output.control.current_task_id) { "Task:    $($output.control.current_task_id)" }
  if ($output.control.stop_reason) { "Reason:  $($output.control.stop_reason)" }
  if ($output.control.degraded_reason) { "Degraded:$($output.control.degraded_reason)" }
  if ($output.control.last_error) { "Error:   $($output.control.last_error)" }
}

$script:Config = New-ControlApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

switch ($Command) {
  "status" {
    Write-ControlResult (Get-ProjectControl)
  }
  "start" {
    $patch = @{ state = "running"; stop_requested = $false; stop_reason = $null; last_error = $null }
    if ($MaxTasks -gt 0) { $patch.max_tasks = $MaxTasks }
    Write-ControlResult (Set-ProjectControl -Patch $patch)
  }
  "pause" {
    Write-ControlResult (Set-ProjectControl -Patch @{
      state = "paused"
      stop_requested = $false
      stop_reason = "operator_paused"
    })
  }
  "stop" {
    Write-ControlResult (Set-ProjectControl -Patch @{
      state = "stopped"
      stop_requested = $true
      stop_reason = "operator_stopped"
    })
  }
  "set-max-tasks" {
    if ($MaxTasks -lt 1) { throw "set-max-tasks requires -MaxTasks greater than zero." }
    Write-ControlResult (Set-ProjectControl -Patch @{ max_tasks = $MaxTasks })
  }
}
