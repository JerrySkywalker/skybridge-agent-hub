[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("Status", "StartNext", "RepairPR", "NightlyReport", "NotifyTest", "AutoMergeSweepDryRun", "HermesHealth", "HermesRunSmoke", "NightlySweep", "SweepAndNotify")]
  [string]$Mode,

  [switch]$DryRun,

  [string]$SkyBridgeApiBase = "http://127.0.0.1:8787",

  [string]$ConfigFile = ".\config\iteration-controller.example.json",

  [int]$PR = 0,

  [switch]$UseHermesApi,

  [string]$HermesApiBase,

  [string]$HermesApiKey,

  [switch]$Send,

  [switch]$EnableAutoMerge,

  [string]$PolicyFile,

  [switch]$Json
)

$ErrorActionPreference = "Stop"

$bootstrapEnvLoader = Join-Path $PSScriptRoot "load-bootstrap-env.ps1"
if (Test-Path -LiteralPath $bootstrapEnvLoader -PathType Leaf) {
  . $bootstrapEnvLoader
}

$hermesEnvLoader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $hermesEnvLoader -PathType Leaf) {
  . $hermesEnvLoader
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $HermesApiBase = $env:HERMES_API_BASE
}
if ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $HermesApiKey = $env:HERMES_API_KEY
}

function Invoke-Bootstrap {
  param([string]$Severity, [string]$Title, [string]$Message)

  $arguments = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\notify-bootstrap.ps1",
    "-Title", $Title,
    "-Message", $Message,
    "-Severity", $Severity,
    "-Json"
  )
  if ($Send) {
    $arguments += "-Send"
  } else {
    $arguments += "-DryRun"
  }

  $output = & pwsh @arguments
  if ($LASTEXITCODE -ne 0) {
    return @{
      ok = $false
      send_requested = [bool]$Send
      error = "bootstrap_notification_failed"
      raw_output_included = $false
    }
  }
  return (($output | ConvertFrom-Json))
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

function Invoke-HermesSmoke {
  param(
    [ValidateSet("api", "run")]
    [string]$Kind
  )

  $savedBase = $env:HERMES_API_BASE
  $savedKey = $env:HERMES_API_KEY
  try {
    if (-not [string]::IsNullOrWhiteSpace($HermesApiBase)) {
      $env:HERMES_API_BASE = $HermesApiBase
    }
    if (-not [string]::IsNullOrWhiteSpace($HermesApiKey)) {
      $env:HERMES_API_KEY = $HermesApiKey
    }

    $scriptName = if ($Kind -eq "run") { "smoke-hermes-cloud-run.ps1" } else { "smoke-hermes-cloud-api.ps1" }
    $arguments = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\$scriptName",
      "-Json"
    )
    if ($DryRun) { $arguments += "-DryRun" }
    $result = Invoke-SafeJsonCommand -Label "hermes_$Kind" -Arguments $arguments
    $result.command_preview = "pwsh -File .\scripts\powershell\$scriptName -Json" + $(if ($DryRun) { " -DryRun" } else { "" })
    return $result
  } finally {
    if ($null -eq $savedBase) {
      Remove-Item -Path "Env:HERMES_API_BASE" -ErrorAction SilentlyContinue
    } else {
      $env:HERMES_API_BASE = $savedBase
    }
    if ($null -eq $savedKey) {
      Remove-Item -Path "Env:HERMES_API_KEY" -ErrorAction SilentlyContinue
    } else {
      $env:HERMES_API_KEY = $savedKey
    }
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

function Get-GitHubPullRequestSummary {
  try {
    $jsonText = gh pr list --state open --limit 20 --json number,title,url,headRefName,isDraft 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonText)) {
      return @{ available = $false; reason = "gh_pr_list_failed"; raw_output_included = $false }
    }
    $items = @($jsonText | ConvertFrom-Json)
    return @{
      available = $true
      open_count = $items.Count
      ai_open_count = @($items | Where-Object { $_.headRefName -like "ai/*" }).Count
      prs = @($items | ForEach-Object {
        @{
          number = $_.number
          title = $_.title
          url = $_.url
          branch = $_.headRefName
          draft = [bool]$_.isDraft
        }
      })
      raw_output_included = $false
    }
  } catch {
    return @{ available = $false; reason = $_.Exception.Message; raw_output_included = $false }
  }
}

$status = Get-SupervisorStatus -ApiBase $SkyBridgeApiBase
$nextAction = Get-NextAction -ApiBase $SkyBridgeApiBase
$github = Get-GitHubPullRequestSummary
$actions = @()
$notification = $null
$hermes = $null

if ($UseHermesApi -and $Mode -in @("Status", "NightlyReport", "HermesHealth", "NotifyTest", "AutoMergeSweepDryRun", "NightlySweep", "SweepAndNotify")) {
  $hermes = Invoke-HermesSmoke -Kind "api"
}
if ($UseHermesApi -and $Mode -eq "HermesRunSmoke") {
  $hermes = Invoke-HermesSmoke -Kind "run"
}

switch ($Mode) {
  "Status" {
    if ($status.ok -eq $false -and $Send) {
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
    $args = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\skybridge-nightly-supervisor-report.ps1",
      "-Json"
    )
    if ($DryRun) { $args += "-DryRun" }
    if ($UseHermesApi) { $args += "-UseHermesApi" }
    if ($Send) { $args += "-Send" }
    if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $args += @("-PolicyFile", $PolicyFile) }
    $actions += Invoke-SafeJsonCommand -Label "nightly_report" -Arguments $args
  }
  "AutoMergeSweepDryRun" {
    $args = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
      "-Json",
      "-SuppressBlockedNotifications"
    )
    if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $args += @("-PolicyFile", $PolicyFile) }
    $actions += Invoke-SafeJsonCommand -Label "auto_merge_sweep_dry_run" -Arguments $args
  }
  "NightlySweep" {
    $args = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
      "-Json",
      "-SuppressBlockedNotifications"
    )
    if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $args += @("-PolicyFile", $PolicyFile) }
    if ($EnableAutoMerge) { $args += "-EnableAutoMerge" }
    $sweepAction = Invoke-SafeJsonCommand -Label "nightly_sweep" -Arguments $args
    $actions += $sweepAction
    if ($Send) {
      $counts = $sweepAction.json.policy_counts
      $message = "Nightly sweep completed: open=$($sweepAction.json.total_open_prs), eligible=$($counts.eligible), blocked=$($counts.blocked), draft=$($counts.draft), non_ai=$($counts.non_ai_branch), missing_checks=$($counts.missing_checks), pending_checks=$($counts.pending_checks), auto_merge=$EnableAutoMerge."
      $notification = Invoke-Bootstrap -Severity "info" -Title "SkyBridge nightly sweep" -Message $message
    }
  }
  "SweepAndNotify" {
    $args = @(
      "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
      "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
      "-Json",
      "-SuppressBlockedNotifications"
    )
    if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $args += @("-PolicyFile", $PolicyFile) }
    if ($EnableAutoMerge) { $args += "-EnableAutoMerge" }
    $sweepAction = Invoke-SafeJsonCommand -Label "sweep_and_notify" -Arguments $args
    $actions += $sweepAction
    if ($Send) {
      $counts = $sweepAction.json.policy_counts
      $message = "Sweep summary: open=$($sweepAction.json.total_open_prs), eligible=$($counts.eligible), blocked=$($counts.blocked), high_risk=$($counts.high_risk_files), missing_checks=$($counts.missing_checks), pending_checks=$($counts.pending_checks), auto_merge=$EnableAutoMerge."
      $notification = Invoke-Bootstrap -Severity "info" -Title "SkyBridge sweep summary" -Message $message
    }
  }
  "NotifyTest" {
    $notification = Invoke-Bootstrap -Severity "info" -Title "SkyBridge Hermes notify test" -Message "Hermes supervisor bootstrap notification test."
  }
  "HermesHealth" {
    if (-not $UseHermesApi) {
      $hermes = @{
        label = "hermes_api"
        exit_code = 0
        json = @{ ok = $false; status = "use_hermes_api_required"; raw_body_included = $false }
        raw_output_included = $false
      }
    }
  }
  "HermesRunSmoke" {
    if (-not $UseHermesApi) {
      $hermes = @{
        label = "hermes_run"
        exit_code = 0
        json = @{ ok = $false; status = "use_hermes_api_required"; raw_response_included = $false }
        raw_output_included = $false
      }
    }
  }
}

$blocked = $false
if ($status.iterations -and $status.iterations.latest) {
  $blocked = $status.iterations.latest.state -in @("blocked", "failed")
}

if ($blocked -and -not $notification -and $Send) {
  $notification = Invoke-Bootstrap -Severity "urgent" -Title "SkyBridge iteration blocked" -Message "Hermes observed a blocked or failed autonomous iteration."
}

$summary = @{
  ok = $true
  mode = $Mode
  dry_run = [bool]$DryRun
  send_requested = [bool]$Send
  enable_auto_merge_requested = [bool]$EnableAutoMerge
  use_hermes_api = [bool]$UseHermesApi
  skybridge_api_base = $SkyBridgeApiBase
  hermes_api_base_configured = -not [string]::IsNullOrWhiteSpace($HermesApiBase)
  hermes_api_base = if ([string]::IsNullOrWhiteSpace($HermesApiBase)) { $null } else { $HermesApiBase }
  hermes_api_key_present = -not [string]::IsNullOrWhiteSpace($HermesApiKey)
  hermes_api_key_value_included = $false
  ssh_tunnel_likely = if ([string]::IsNullOrWhiteSpace($HermesApiBase)) { $false } else { $HermesApiBase -match "127\.0\.0\.1|localhost|\[::1\]" }
  status = $status
  next_action = $nextAction
  github = $github
  hermes = $hermes
  actions = $actions
  bootstrap_notification = $notification
  raw_logs_included = $false
  raw_prompts_included = $false
  safety = @{
    production_deploy = $false
    branch_protection_mutated = $false
    auto_merge_enabled_by_default = $false
    auto_merge_sweep_dry_run_only = -not [bool]$EnableAutoMerge
    auto_merge_requires_enable_flag = $true
    skybridge_server_required_for_dry_run = $false
    notification_center_required = $false
    phone_notification_requires_send = $true
  }
}

if ($Json -or $true) {
  $summary | ConvertTo-Json -Depth 24
}
