param(
  [Parameter(Mandatory=$true)]
  [string]$Title,

  [Parameter(Mandatory=$true)]
  [string]$Message,

  [ValidateSet("min", "low", "default", "high", "urgent")]
  [string]$Priority = "default",

  [string]$Url = $env:NTFY_URL,

  [string]$Topic = $env:NTFY_TOPIC
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($Topic)) {
  Write-Host "[notify-ntfy] skipped: NTFY_URL or NTFY_TOPIC is empty."
  exit 0
}

$headers = @{
  "Title" = $Title
  "Priority" = $Priority
  "Tags" = "robot"
}

if ($env:NTFY_USER -and $env:NTFY_PASSWORD) {
  $pair = "$($env:NTFY_USER):$($env:NTFY_PASSWORD)"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
  $headers["Authorization"] = "Basic " + [Convert]::ToBase64String($bytes)
}

Invoke-RestMethod -Method Post -Uri "$Url/$Topic" -Headers $headers -Body $Message | Out-Null
