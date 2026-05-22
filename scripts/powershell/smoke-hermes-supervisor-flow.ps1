[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Invoke-Hermes {
  param([string]$Mode, [switch]$DryRun, [int]$PR = 0)
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\skybridge-hermes-supervisor.ps1",
    "-Mode", $Mode,
    "-SkyBridgeApiBase", "http://127.0.0.1:1",
    "-ConfigFile", ".\config\iteration-controller.example.json"
  )
  if ($DryRun) { $args += "-DryRun" }
  if ($PR -gt 0) { $args += @("-PR", [string]$PR) }
  $output = & pwsh @args
  if ($LASTEXITCODE -ne 0) {
    throw "Hermes supervisor mode $Mode failed"
  }
  return (($output) -join "`n") | ConvertFrom-Json
}

$status = Invoke-Hermes -Mode "Status" -DryRun
$startNext = Invoke-Hermes -Mode "StartNext" -DryRun
$repair = Invoke-Hermes -Mode "RepairPR" -DryRun -PR 999999
$report = Invoke-Hermes -Mode "NightlyReport" -DryRun

foreach ($result in @($status, $startNext, $repair, $report)) {
  if ($result.raw_logs_included -ne $false -or $result.raw_prompts_included -ne $false) {
    throw "Hermes smoke result exposed raw logs or prompts"
  }
  if ($result.safety.production_deploy -ne $false) {
    throw "Hermes smoke attempted production deployment"
  }
}

@{
  ok = $true
  status_mode = $status.mode
  start_next_actions = $startNext.actions.Count
  repair_actions = $repair.actions.Count
  nightly_mode = $report.mode
  operator_summary = "Hermes dry-run flow validated without SkyBridge server, credentials or real Hermes runtime."
} | ConvertTo-Json -Depth 8
