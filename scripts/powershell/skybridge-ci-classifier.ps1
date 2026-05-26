[CmdletBinding()]
param(
  [string]$LogFile,
  [string]$Text,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-SkyBridgeCiClassification {
  param([string]$LogText, [string]$CheckState = "")

  $text = if ($null -eq $LogText) { "" } else { $LogText }
  $state = $CheckState.ToLowerInvariant()
  $reasons = @()
  $classification = "ci_unknown"

  if ($state -in @("success", "passed", "green")) {
    $classification = "ci_green"
  } elseif ($state -in @("pending", "queued", "in_progress", "waiting")) {
    $classification = "ci_pending"
  } elseif ($text -match "(?i)Your account is suspended") {
    $classification = "ci_blocked_account_suspended_message"
    $reasons += "github_account_suspended_message"
  } elseif ($text -match "(?i)(actions/checkout|git fetch|expected 'packfile'|RPC failed|unable to access|HTTP 403|checkout)") {
    if ($text -match "(?i)(HTTP 403|requested URL returned error: 403|expected 'packfile'|RPC failed)") {
      $classification = "ci_blocked_checkout_403"
      $reasons += "checkout_or_fetch_403"
    } else {
      $classification = "ci_transient_checkout_or_fetch_failure"
      $reasons += "checkout_or_fetch_failure"
    }
  } elseif ($text -match "(?i)(Failed to download archive|codeload.github.com|Could not resolve host|TLS|timed out|ECONNRESET|network)") {
    $classification = "ci_transient_checkout_or_fetch_failure"
    $reasons += "dependency_or_network_fetch_failure"
  } elseif ($state -in @("failure", "failed", "cancelled", "timed_out", "action_required") -or $text -match "(?i)(##\\[error\\]|failed|error)") {
    $classification = "ci_failed_real"
    $reasons += "check_failed"
  }

  [pscustomobject]@{
    classification = $classification
    recovered = ($classification -eq "ci_green")
    reasons = @($reasons)
  }
}

if ($MyInvocation.PSCommandPath -eq $PSCommandPath) {
  $logText = $Text
  if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    $logText = Get-Content -Raw -LiteralPath $LogFile
  }
  $result = Get-SkyBridgeCiClassification -LogText $logText
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress }
  else { $result | Format-List }
}
