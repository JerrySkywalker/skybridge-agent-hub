[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet("goal","project","workers","tasks","task","loop")][string]$Area,
  [Parameter(Mandatory = $true)][string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId = "self-bootstrap-smoke",
  [string]$TaskId,
  [string]$MasterGoalFile = ".\goals\master\self-bootstrap-smoke.md",
  [int]$MaxRounds = 3,
  [int]$MaxTasks = 0,
  [switch]$DryRun,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Write-CliResult {
  param($Result)
  if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List }
}

switch ("$Area $Command") {
  "goal submit" {
    $project = $null
    try { $project = Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase } catch {}
    if (-not $project) {
      Invoke-SkyBridgeApi -Method POST -Path "/v1/projects" -ApiBase $ApiBase -Body @{ project_id = $ProjectId; name = "SkyBridge Agent Hub" } | Out-Null
    }
    $goal = Invoke-SkyBridgeApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -ApiBase $ApiBase -Body @{ goal_id = $GoalId; title = "Hermes self-bootstrap smoke"; summary = (Get-Content -Raw -LiteralPath $MasterGoalFile) }
    Write-CliResult $goal
  }
  "project run" {
    $args = @("-File", ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1", "-MasterGoalFile", $MasterGoalFile, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-MaxRounds", [string]$MaxRounds, "-Json")
    if ($DryRun) { $args += "-DryRun" }
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  "project status" {
    Write-CliResult @{
      project = (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase)
      control = (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase)
      goal = (Invoke-SkyBridgeApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($GoalId))" -ApiBase $ApiBase)
      tasks = (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase)
    }
  }
  "project start" {
    $patch = @{ state = "running"; stop_requested = $false; stop_reason = $null; last_error = $null }
    if ($MaxRounds -gt 0) { $patch.max_rounds = $MaxRounds }
    if ($MaxTasks -gt 0) { $patch.max_tasks = $MaxTasks }
    Write-CliResult (Invoke-SkyBridgeApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Body $patch)
  }
  "project pause" {
    Write-CliResult (Invoke-SkyBridgeApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Body @{
      state = "paused"
      stop_requested = $false
      stop_reason = "operator_paused"
    })
  }
  "project resume" {
    Write-CliResult (Invoke-SkyBridgeApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Body @{
      state = "running"
      stop_requested = $false
      degraded_reason = $null
      stop_reason = $null
    })
  }
  "project stop" {
    Write-CliResult (Invoke-SkyBridgeApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Body @{
      state = "stopped"
      stop_requested = $true
      stop_reason = "operator_stopped"
    })
  }
  "workers list" { Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $ApiBase) }
  "tasks list" { Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase) }
  "task show" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "task show requires -TaskId." }
    Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase)
  }
  "loop run-once" {
    $args = @("-File", ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1", "-MasterGoalFile", $MasterGoalFile, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-MaxRounds", "1", "-Json")
    if ($DryRun) { $args += "-DryRun" }
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  "loop run-max-rounds" {
    $args = @("-File", ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1", "-MasterGoalFile", $MasterGoalFile, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-MaxRounds", [string]$MaxRounds, "-Json")
    if ($DryRun) { $args += "-DryRun" }
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  default {
    throw "Unsupported command. Supported: goal submit, project run, project start, project pause, project resume, project stop, project status, workers list, tasks list, task show, loop run-once, loop run-max-rounds."
  }
}
