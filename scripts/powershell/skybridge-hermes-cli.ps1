[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet("goal","project","workers","worker","tasks","task","loop","operator")][string]$Area,
  [Parameter(Mandatory = $true)][string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId = "self-bootstrap-smoke",
  [string]$GoalTitle,
  [string]$MasterGoalId,
  [string]$ProposalId,
  [string]$Description,
  [string[]]$Constraints = @(),
  [int]$MaxRounds = 3,
  [string]$TaskId,
  [string]$TaskTitle,
  [string]$TaskBody,
  [string]$TaskBodyFile,
  [string]$WorkerProfile,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$MasterGoalFile = ".\goals\master\self-bootstrap-smoke.md",
  [int]$MaxTasks = 0,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Write-CliResult {
  param($Result)
  if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List }
}

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function Invoke-OperatorGuide {
  param([string]$Mode)
  $args = @("-File", ".\scripts\powershell\skybridge-guide.ps1", "-Mode", $Mode, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
  if ($GoalId) { $args += @("-GoalId", $GoalId) }
  if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
  if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
  if ($ProposalId) { $args += @("-ProposalId", $ProposalId) }
  if ($Description) { $args += @("-Description", $Description) }
  foreach ($constraint in @($Constraints)) { $args += @("-Constraints", $constraint) }
  if ($TaskId) { $args += @("-TaskId", $TaskId) }
  if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) }
  if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
  if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
  if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
  if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  if ($Apply) { $args += "-Apply" }
  if ($DryRun) { $args += "-DryRun" }
  if ($MaxRounds -gt 0) { $args += @("-MaxRounds", [string]$MaxRounds) }
  Write-CliResult (Invoke-JsonScript -Arguments $args)
}

switch ("$Area $Command") {
  "operator status" { Invoke-OperatorGuide -Mode "status" }
  "operator submit-preview" { Invoke-OperatorGuide -Mode "submit-preview" }
  "operator submit-apply" { Invoke-OperatorGuide -Mode "submit-apply" }
  "operator run-once-preview" { Invoke-OperatorGuide -Mode "run-once-preview" }
  "operator run-once-apply" { Invoke-OperatorGuide -Mode "run-once-apply" }
  "operator inspect-task" { Invoke-OperatorGuide -Mode "inspect-task" }
  "operator inspect-worker" { Invoke-OperatorGuide -Mode "inspect-worker" }
  "operator pause" { Invoke-OperatorGuide -Mode "pause" }
  "operator start" { Invoke-OperatorGuide -Mode "start" }
  "operator plan-preview" { Invoke-OperatorGuide -Mode "plan-preview" }
  "operator plan-apply" { Invoke-OperatorGuide -Mode "plan-apply" }
  "operator proposals" { Invoke-OperatorGuide -Mode "proposals" }
  "operator proposal-show" { Invoke-OperatorGuide -Mode "proposal-show" }
  "operator proposal-accept" { Invoke-OperatorGuide -Mode "proposal-accept" }
  "operator proposal-convert-preview" { Invoke-OperatorGuide -Mode "proposal-convert-preview" }
  "operator supervise-preview" { Invoke-OperatorGuide -Mode "supervise-preview" }
  "operator supervise-apply" { Invoke-OperatorGuide -Mode "supervise-apply" }
  "goal submit" {
    $args = @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-EnsureProject", "-EnsureGoal", "-Json")
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) } else { $args += @("-GoalTitle", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) } else { $args += @("-TaskTitle", "Operator submitted task") }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    elseif ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    elseif (Test-Path -LiteralPath $MasterGoalFile -PathType Leaf) { $args += @("-TaskBodyFile", $MasterGoalFile) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    Write-CliResult (Invoke-JsonScript -Arguments $args)
  }
  "goal list" {
    Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -ApiBase $ApiBase)
  }
  "task create" {
    $args = @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-EnsureProject", "-EnsureGoal", "-Json")
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) } else { $args += @("-GoalTitle", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) } else { throw "task create requires -TaskTitle." }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    Write-CliResult (Invoke-JsonScript -Arguments $args)
  }
  "project run" {
    $args = @("-File", ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1", "-MasterGoalFile", $MasterGoalFile, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-MaxRounds", [string]$MaxRounds, "-Json")
    if ($DryRun) { $args += "-DryRun" }
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  "project status" {
    $args = @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    Write-CliResult (Invoke-JsonScript -Arguments $args)
  }
  "project start" {
    $args = @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "start", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    if ($MaxTasks -gt 0) { $args += @("-MaxTasks", [string]$MaxTasks) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    Write-CliResult (Invoke-JsonScript -Arguments $args)
  }
  "project pause" {
    $args = @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    Write-CliResult (Invoke-JsonScript -Arguments $args)
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
  "worker status" {
    if ([string]::IsNullOrWhiteSpace($WorkerProfile)) { throw "worker status requires -WorkerProfile." }
    Write-CliResult (Invoke-JsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-Json"))
  }
  "worker heartbeat" {
    if ([string]::IsNullOrWhiteSpace($WorkerProfile)) { throw "worker heartbeat requires -WorkerProfile." }
    Write-CliResult (Invoke-JsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "register-heartbeat", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-Json"))
  }
  "tasks list" { Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase) }
  "task show" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "task show requires -TaskId." }
    Write-CliResult (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase)
  }
  "loop run-once" {
    $args = @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-Json")
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
    if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $args += "-NoSubmit"
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  "loop run-max-rounds" {
    $args = @("-File", ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1", "-MasterGoalFile", $MasterGoalFile, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalId", $GoalId, "-MaxRounds", [string]$MaxRounds, "-Json")
    if ($DryRun) { $args += "-DryRun" }
    Write-CliResult ((& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args) | ConvertFrom-Json)
  }
  default {
    throw "Unsupported command. Supported: operator status, operator submit-preview, operator run-once-preview, operator inspect-task, goal submit, project run, project start, project pause, project resume, project stop, project status, workers list, tasks list, task show, loop run-once, loop run-max-rounds."
  }
}
