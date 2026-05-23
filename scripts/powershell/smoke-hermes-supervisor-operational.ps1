[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Invoke-HermesMode {
  param([string]$Mode, [int]$PR = 0)
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\skybridge-hermes-supervisor.ps1",
    "-Mode", $Mode,
    "-DryRun",
    "-SkyBridgeApiBase", "http://127.0.0.1:1",
    "-ConfigFile", ".\config\iteration-controller.example.json"
  )
  if ($PR -gt 0) { $args += @("-PR", [string]$PR) }
  $output = & pwsh @args
  if ($LASTEXITCODE -ne 0) {
    throw "Hermes mode $Mode failed"
  }
  return (($output) -join "`n") | ConvertFrom-Json
}

$modes = @("Status", "StartNext", "RepairPR", "NightlyReport", "NotifyTest")
$results = @()
foreach ($mode in $modes) {
  $result = Invoke-HermesMode -Mode $mode
  if ($result.mode -ne $mode) {
    throw "Hermes mode $mode returned unexpected mode $($result.mode)"
  }
  if ($result.raw_logs_included -ne $false -or $result.raw_prompts_included -ne $false) {
    throw "Hermes mode $mode exposed raw logs or prompts"
  }
  if ($result.safety.production_deploy -ne $false -or $result.safety.branch_protection_mutated -ne $false) {
    throw "Hermes mode $mode crossed a safety boundary"
  }
  if ($result.safety.skybridge_server_required_for_dry_run -ne $false) {
    throw "Hermes mode $mode required SkyBridge server for dry-run"
  }
  $results += $result
}

@{
  ok = $true
  dry_run = $true
  modes = $results.mode
  start_next_actions = ($results | Where-Object { $_.mode -eq "StartNext" }).actions.Count
  repair_preview = (($results | Where-Object { $_.mode -eq "RepairPR" }).actions | Select-Object -First 1).json.action
  notify_test_status = ($results | Where-Object { $_.mode -eq "NotifyTest" }).bootstrap_notification.ok
  skybridge_server_required = $false
} | ConvertTo-Json -Depth 8
