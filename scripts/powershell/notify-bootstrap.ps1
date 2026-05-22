[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Title,

  [Parameter(Mandatory=$true)]
  [string]$Message,

  [ValidateSet("info", "warning", "urgent")]
  [string]$Severity = "info",

  [switch]$DryRun,

  [switch]$Json,

  [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

function Join-NtfyTopicUrl {
  if (-not [string]::IsNullOrWhiteSpace($env:NTFY_TOPIC_URL)) {
    return $env:NTFY_TOPIC_URL
  }

  if ([string]::IsNullOrWhiteSpace($env:NTFY_URL) -or [string]::IsNullOrWhiteSpace($env:NTFY_TOPIC)) {
    return $null
  }

  return "$($env:NTFY_URL.TrimEnd('/'))/$($env:NTFY_TOPIC.TrimStart('/'))"
}

function Convert-SeverityToNtfyPriority {
  param([string]$Value)
  switch ($Value) {
    "urgent" { return "urgent" }
    "warning" { return "high" }
    default { return "default" }
  }
}

function Convert-SeverityToWeComMention {
  param([string]$Value)
  if ($Value -eq "urgent") {
    return @("@all")
  }
  return @()
}

function Send-NtfyBootstrap {
  param(
    [string]$TopicUrl,
    [string]$Title,
    [string]$Message,
    [string]$Severity
  )

  $headers = @{
    "Title" = $Title
    "Priority" = Convert-SeverityToNtfyPriority -Value $Severity
    "Tags" = "robot"
  }

  if (-not [string]::IsNullOrWhiteSpace($env:NTFY_TOKEN)) {
    $headers["Authorization"] = "Bearer $($env:NTFY_TOKEN)"
  } elseif (-not [string]::IsNullOrWhiteSpace($env:NTFY_USER) -and -not [string]::IsNullOrWhiteSpace($env:NTFY_PASSWORD)) {
    $pair = "$($env:NTFY_USER):$($env:NTFY_PASSWORD)"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
    $headers["Authorization"] = "Basic " + [Convert]::ToBase64String($bytes)
  }

  Invoke-RestMethod -Method Post -Uri $TopicUrl -Headers $headers -Body $Message -TimeoutSec $TimeoutSeconds | Out-Null
}

function Send-WeComBootstrap {
  param(
    [string]$WebhookUrl,
    [string]$Title,
    [string]$Message,
    [string]$Severity
  )

  $mentions = Convert-SeverityToWeComMention -Value $Severity
  $body = @{
    msgtype = "text"
    text = @{
      content = "[$Severity] $Title`n$Message"
      mentioned_list = $mentions
    }
  } | ConvertTo-Json -Depth 8 -Compress

  Invoke-RestMethod -Method Post -Uri $WebhookUrl -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSeconds | Out-Null
}

$ntfyTopicUrl = Join-NtfyTopicUrl
$wecomWebhookUrl = $env:WECOM_WEBHOOK_URL
$results = @()

if ($DryRun) {
  $results += @{
    provider = "ntfy"
    status = if ($ntfyTopicUrl) { "configured" } else { "skipped" }
    reason = if ($ntfyTopicUrl) { "dry_run" } else { "missing_ntfy_env" }
  }
  $results += @{
    provider = "wecom"
    status = if ($Severity -eq "urgent" -and -not [string]::IsNullOrWhiteSpace($wecomWebhookUrl)) { "configured" } else { "skipped" }
    reason = if ($Severity -eq "urgent") { "dry_run_or_missing_webhook" } else { "urgent_only" }
  }
} else {
  if ($ntfyTopicUrl) {
    try {
      Send-NtfyBootstrap -TopicUrl $ntfyTopicUrl -Title $Title -Message $Message -Severity $Severity
      $results += @{ provider = "ntfy"; status = "sent"; reason = "ok" }
    } catch {
      $results += @{ provider = "ntfy"; status = "failed"; reason = $_.Exception.Message }
    }
  } else {
    $results += @{ provider = "ntfy"; status = "skipped"; reason = "missing_ntfy_env" }
  }

  if ($Severity -eq "urgent" -and -not [string]::IsNullOrWhiteSpace($wecomWebhookUrl)) {
    try {
      Send-WeComBootstrap -WebhookUrl $wecomWebhookUrl -Title $Title -Message $Message -Severity $Severity
      $results += @{ provider = "wecom"; status = "sent"; reason = "ok" }
    } catch {
      $results += @{ provider = "wecom"; status = "failed"; reason = $_.Exception.Message }
    }
  } else {
    $results += @{
      provider = "wecom"
      status = "skipped"
      reason = if ($Severity -eq "urgent") { "missing_wecom_webhook" } else { "urgent_only" }
    }
  }
}

$summary = @{
  ok = -not ($results | Where-Object { $_.status -eq "failed" })
  dry_run = [bool]$DryRun
  severity = $Severity
  title = $Title
  direct_notification_dependency = "none"
  skybridge_server_required = $false
  results = $results
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  foreach ($result in $results) {
    Write-Host "[bootstrap-notify] $($result.provider) $($result.status): $($result.reason)"
  }
}

if (-not $summary.ok) {
  exit 1
}
