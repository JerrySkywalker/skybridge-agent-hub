[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Title,

  [Parameter(Mandatory=$true)]
  [string]$Message,

  [ValidateSet("info", "warning", "urgent")]
  [string]$Severity = "info",

  [switch]$DryRun,

  [switch]$Send,

  [switch]$Json,

  [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

function Join-NtfyTopicUrl {
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC)) {
    $base = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_URL)) { $env:SKYBRIDGE_BOOTSTRAP_NTFY_URL } else { "https://ntfy.sh" }
    $topic = if ($Severity -eq "urgent" -and -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC)) {
      $env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC
    } else {
      $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC
    }
    return "$($base.TrimEnd('/'))/$($topic.TrimStart('/'))"
  }

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

  $token = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN)) { $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN } else { $env:NTFY_TOKEN }
  $user = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_USER)) { $env:SKYBRIDGE_BOOTSTRAP_NTFY_USER } else { $env:NTFY_USER }
  $password = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS)) { $env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS } else { $env:NTFY_PASSWORD }

  if (-not [string]::IsNullOrWhiteSpace($token)) {
    $headers["Authorization"] = "Bearer $token"
  } elseif (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($password)) {
    $pair = "$($user):$($password)"
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
$wecomWebhookUrl = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK)) { $env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK } else { $env:WECOM_WEBHOOK_URL }
$results = @()
$sendRequested = [bool]$Send -and -not [bool]$DryRun

if (-not $sendRequested) {
  $results += @{
    provider = "ntfy"
    status = if ($ntfyTopicUrl) { "configured" } else { "skipped" }
    reason = if ($DryRun) { "dry_run" } elseif ($ntfyTopicUrl) { "send_flag_required" } else { "missing_ntfy_env" }
  }
  $results += @{
    provider = "wecom"
    status = if ($Severity -eq "urgent" -and -not [string]::IsNullOrWhiteSpace($wecomWebhookUrl)) { "configured" } else { "skipped" }
    reason = if ($DryRun) { "dry_run_or_missing_webhook" } elseif ($Severity -eq "urgent") { "send_flag_required_or_missing_webhook" } else { "urgent_only" }
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
  dry_run = [bool](-not $sendRequested)
  send_requested = $sendRequested
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
