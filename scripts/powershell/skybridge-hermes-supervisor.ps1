[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("Status", "StartNext", "RepairPR", "NightlyReport", "NotifyTest")]
  [string]$Mode,

  [switch]$DryRun,

  [string]$SkyBridgeApiBase = "http://127.0.0.1:8787",

  [string]$ConfigFile = ".\config\iteration-controller.example.json",

  [int]$PR = 0
)

$ErrorActionPreference = "Stop"

$bootstrapEnvLoader = Join-Path $PSScriptRoot "load-bootstrap-env.ps1"
if (Test-Path -LiteralPath $bootstrapEnvLoader -PathType Leaf) {
  . $bootstrapEnvLoader
}

function Invoke-Bootstrap {
  param([string]$Severity, [string]$Title, [string]$Message)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title $Title `
    -Message $Message `
    -Severity $Severity `
    -DryRun:$DryRun `
    -Json
  return ($output | ConvertFrom-Json)
}

function Invoke-SafeJsonCommand {
  param([string]$Label, [string[]]$Arguments)
  $output = & pwsh @Arguments
  $exitCode = $LASTEXITCODE
  $jsonStartIndex = [Array]::FindIndex([string[]]$output, [Predicate[string]]{ param($line) $line -match "^\s*\{" })
  $parsed = $null
  if ($jsonStartIndex -ge 0) {
    try {
      $parsed = (($output | Select-Object -Skip $jsonStartIndex) -join "`n") | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
  }
  return @{
    label = $Label
    exit_code = $exitCode
    json = $parsed
    command_preview = "pwsh " + (($Arguments | Where-Object { $_ -notmatch "^-NoLogo$|^-NoProfile$" }) -join " ")
    raw_output_included = $false
  }
}

function Get-SupervisorStatus {
  param([string]$ApiBase)
  try {
    return Invoke-RestMethod -Method Get -Uri "$($ApiBase.TrimEnd('/'))/v1/supervisor/status" -TimeoutSec 4
  } catch {
    return @{
      ok = $false
      error = "skybridge_unavailable"
      message = $_.Exception.Message
      raw_logs_included = $false
      raw_prompts_included = $false
    }
  }
}

function Get-NextAction {
  param([string]$ApiBase)
  try {
    return Invoke-RestMethod -Method Get -Uri "$($ApiBase.TrimEnd('/'))/v1/supervisor/next-action" -TimeoutSec 4
  } catch {
    return @{
      action = "observe"
      reason = "skybridge_unavailable"
    }
  }
}

$status = Get-SupervisorStatus -ApiBase $SkyBridgeApiBase
$nextAction = Get-NextAction -ApiBase $SkyBridgeApiBase
$actions = @()
$notification = $null

switch ($Mode) {
  "Status" {
    if ($status.ok -eq $false) {
      $notification = Invoke-Bootstrap -Severity "warning" -Title "SkyBridge supervisor degraded" -Message "SkyBridge status endpoint is unavailable."
    }
  }
  "StartNext" {
    $args = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\skybridge-iterate.ps1",
      "-ConfigFile", $ConfigFile,
      "-One",
      "-NoAutoMerge",
      "-SkyBridgeApiBase", $SkyBridgeApiBase
    )
    if ($DryRun) { $args += "-DryRun" }
    $actions += Invoke-SafeJsonCommand -Label "start_next" -Arguments $args
  }
  "RepairPR" {
    if ($DryRun -and $PR -le 0) {
      $actions += @{
        label = "repair_pr"
        exit_code = 0
        json = @{
          ok = $true
          dry_run = $true
          action = "repair_pr_preview"
          reason = "no_pr_supplied"
          skybridge_server_required = $false
        }
        command_preview = "pwsh -File .\scripts\powershell\skybridge-ci-guardian.ps1 -PR <number> -DryRun"
        raw_output_included = $false
      }
    } else {
      $args = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", ".\scripts\powershell\skybridge-ci-guardian.ps1",
        "-MaxRepairAttempts", "3",
        "-SkyBridgeApiBase", $SkyBridgeApiBase
      )
      if ($PR -gt 0) {
        $args += @("-PR", [string]$PR)
      } else {
        $args += "-CurrentBranch"
      }
      if ($DryRun) { $args += "-DryRun" }
      $actions += Invoke-SafeJsonCommand -Label "repair_pr" -Arguments $args
    }
  }
  "NightlyReport" {
    if ($status.ok -eq $false) {
      $notification = Invoke-Bootstrap -Severity "warning" -Title "SkyBridge nightly degraded" -Message "SkyBridge status endpoint is unavailable during nightly report."
    }
  }
  "NotifyTest" {
    $notification = Invoke-Bootstrap -Severity "warning" -Title "SkyBridge Hermes notify test" -Message "Hermes supervisor bootstrap notification dry-run."
  }
}

$blocked = $false
if ($status.iterations -and $status.iterations.latest) {
  $blocked = $status.iterations.latest.state -in @("blocked", "failed")
}

if ($blocked -and -not $notification) {
  $notification = Invoke-Bootstrap -Severity "urgent" -Title "SkyBridge iteration blocked" -Message "Hermes observed a blocked or failed autonomous iteration."
}

@{
  ok = $true
  mode = $Mode
  dry_run = [bool]$DryRun
  skybridge_api_base = $SkyBridgeApiBase
  status = $status
  next_action = $nextAction
  actions = $actions
  bootstrap_notification = $notification
  raw_logs_included = $false
  raw_prompts_included = $false
  safety = @{
    production_deploy = $false
    branch_protection_mutated = $false
    auto_merge_enabled_by_default = $false
    skybridge_server_required_for_dry_run = $false
    notification_center_required = $false
  }
} | ConvertTo-Json -Depth 20
