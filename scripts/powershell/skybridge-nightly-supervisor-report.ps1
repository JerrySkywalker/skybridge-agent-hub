[CmdletBinding()]
param(
  [switch]$Json,
  [switch]$Send,
  [switch]$DryRun,
  [switch]$UseHermesApi,
  [string]$SkyBridgeApiBase = "http://127.0.0.1:8787",
  [string]$PolicyFile
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

function Invoke-JsonCommand {
  param([string]$Label, [string[]]$Arguments)

  try {
    $output = & pwsh @Arguments
    $exitCode = $LASTEXITCODE
    $parsed = $null
    try {
      $parsed = (($output) -join "`n") | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
    return [ordered]@{
      label = $Label
      ok = ($exitCode -eq 0)
      exit_code = $exitCode
      json = $parsed
      raw_output_included = $false
    }
  } catch {
    return [ordered]@{
      label = $Label
      ok = $false
      exit_code = 1
      error = $_.Exception.Message
      raw_output_included = $false
    }
  }
}

function Invoke-GhJson {
  param([string[]]$Arguments)

  try {
    $output = & gh @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output -join ""))) {
      return @{ available = $false; reason = "gh_failed"; raw_output_included = $false }
    }
    return @{ available = $true; value = (($output -join "`n") | ConvertFrom-Json); raw_output_included = $false }
  } catch {
    return @{ available = $false; reason = $_.Exception.Message; raw_output_included = $false }
  }
}

function Get-HermesReport {
  if (-not $UseHermesApi) {
    return [ordered]@{
      checked = $false
      status = "skipped"
      reason = "use_hermes_api_not_requested"
      hermes_api_key_value_included = $false
    }
  }

  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\watch-hermes-health.ps1",
    "-Once",
    "-Json"
  )
  return Invoke-JsonCommand -Label "hermes_health" -Arguments $args
}

function Get-GitHubOpenPrSummary {
  $prs = Invoke-GhJson -Arguments @("pr", "list", "--state", "open", "--limit", "30", "--json", "number,title,url,headRefName,isDraft,mergeStateStatus")
  if (-not $prs.available) {
    return [ordered]@{ available = $false; reason = $prs.reason; raw_output_included = $false }
  }
  $items = @($prs.value)
  return [ordered]@{
    available = $true
    open_count = $items.Count
    ai_open_count = @($items | Where-Object { $_.headRefName -like "ai/*" }).Count
    draft_count = @($items | Where-Object { $_.isDraft }).Count
    prs = @($items | ForEach-Object {
      [ordered]@{
        number = $_.number
        title = $_.title
        url = $_.url
        branch = $_.headRefName
        draft = [bool]$_.isDraft
        merge_state = $_.mergeStateStatus
      }
    })
    raw_output_included = $false
  }
}

function Get-GitHubWorkflowSummary {
  $runs = Invoke-GhJson -Arguments @("run", "list", "--limit", "10", "--json", "databaseId,displayTitle,workflowName,status,conclusion,event,headBranch,createdAt,url")
  if (-not $runs.available) {
    return [ordered]@{ available = $false; reason = $runs.reason; raw_output_included = $false }
  }
  $items = @($runs.value)
  $failed = @($items | Where-Object { $_.conclusion -in @("failure", "cancelled", "timed_out", "action_required") })
  $inProgress = @($items | Where-Object { $_.status -ne "completed" })
  return [ordered]@{
    available = $true
    count = $items.Count
    failing = $failed.Count
    in_progress = $inProgress.Count
    latest = @($items | Select-Object -First 5 | ForEach-Object {
      [ordered]@{
        workflow = $_.workflowName
        title = $_.displayTitle
        status = $_.status
        conclusion = $_.conclusion
        event = $_.event
        branch = $_.headBranch
        created_at = $_.createdAt
        url = $_.url
      }
    })
    raw_output_included = $false
  }
}

function Get-SweepDryRunSummary {
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
    "-Json",
    "-SuppressBlockedNotifications"
  )
  if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) {
    $args += @("-PolicyFile", $PolicyFile)
  }
  return Invoke-JsonCommand -Label "auto_merge_sweep_dry_run" -Arguments $args
}

function Get-SkyBridgeApiStatus {
  try {
    $body = Invoke-RestMethod -Method Get -Uri "$($SkyBridgeApiBase.TrimEnd('/'))/health" -TimeoutSec 4
    return [ordered]@{
      available = $true
      api_base = $SkyBridgeApiBase
      properties = @($body.PSObject.Properties | ForEach-Object { $_.Name })
      body_included = $false
    }
  } catch {
    return [ordered]@{
      available = $false
      api_base = $SkyBridgeApiBase
      error = $_.Exception.Message
      body_included = $false
    }
  }
}

function Get-BootstrapNotificationStatus {
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\notify-bootstrap.ps1",
    "-Title", "SkyBridge nightly report dry run",
    "-Message", "Bootstrap notification configuration check.",
    "-Severity", "info",
    "-DryRun",
    "-Json"
  )
  return Invoke-JsonCommand -Label "bootstrap_notification_config" -Arguments $args
}

function Get-ProgressTailSummary {
  $path = ".\docs\dev\PROGRESS.md"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [ordered]@{ available = $false; path = $path; lines = @() }
  }

  $lines = @(Get-Content -LiteralPath $path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 24)
  return [ordered]@{
    available = $true
    path = $path
    lines = @($lines)
    raw_logs_included = $false
  }
}

function Send-NightlySummary {
  param([object]$Report)

  $hermesStatus = if ($Report.hermes.checked -eq $false) { "skipped" } elseif ($Report.hermes.json) { $Report.hermes.json.status } else { "unknown" }
  $message = "Hermes=$hermesStatus; open_prs=$($Report.github.open_prs.open_count); failing_runs=$($Report.github.workflows.failing); sweep_eligible=$($Report.auto_merge_sweep.json.eligible_count); skybridge_api=$($Report.skybridge_api.available)."
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\notify-bootstrap.ps1",
    "-Title", "SkyBridge nightly supervisor report",
    "-Message", $message,
    "-Severity", "info",
    "-Json"
  )
  if ($Send) {
    $args += "-Send"
  } else {
    $args += "-DryRun"
  }
  return Invoke-JsonCommand -Label "nightly_summary_notification" -Arguments $args
}

$report = [ordered]@{
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  dry_run = [bool]$DryRun
  send_requested = [bool]$Send
  use_hermes_api = [bool]$UseHermesApi
  hermes = Get-HermesReport
  github = [ordered]@{
    open_prs = Get-GitHubOpenPrSummary
    workflows = Get-GitHubWorkflowSummary
  }
  auto_merge_sweep = Get-SweepDryRunSummary
  skybridge_api = Get-SkyBridgeApiStatus
  bootstrap_notification_config = Get-BootstrapNotificationStatus
  progress_tail = Get-ProgressTailSummary
  notification = $null
  safety = [ordered]@{
    production_deploy = $false
    secrets_printed = $false
    hermes_api_key_value_included = $false
    notification_send_requires_send_flag = $true
    auto_merge_enabled = $false
    sweep_dry_run_only = $true
    urgent_notification = $false
  }
}

$report.notification = Send-NightlySummary -Report $report
$report.ok = [bool](
  $report.auto_merge_sweep.ok -and
  ($report.github.open_prs.available -or $report.github.open_prs.reason) -and
  ($report.github.workflows.available -or $report.github.workflows.reason)
)

if ($Json) {
  $report | ConvertTo-Json -Depth 24
} else {
  $hermesStatus = if ($report.hermes.checked -eq $false) { "skipped" } elseif ($report.hermes.json) { $report.hermes.json.status } else { "unknown" }
  Write-Host "[nightly-report] hermes=$hermesStatus open_prs=$($report.github.open_prs.open_count) failing_runs=$($report.github.workflows.failing) sweep_eligible=$($report.auto_merge_sweep.json.eligible_count) send=$Send"
}

exit 0
