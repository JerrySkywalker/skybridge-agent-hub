[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\admin-escalation-test-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-AdminTest {
  param([string[]]$ScriptArgs, [switch]$AllowFailure)
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-admin-escalation-test.ps1") @ScriptArgs -Json
  $exitCode = $LASTEXITCODE
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  if ($exitCode -ne 0 -and -not $AllowFailure) { throw "admin escalation send-test failed unexpectedly: $text" }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "admin escalation send-test returned no JSON." }
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.admin_escalation_test.v1") { throw "Unexpected admin escalation test schema." }
  if ($result.channel -ne "hermes-wechat") { throw "Unexpected admin escalation test channel." }
  Assert-True $result.message_redacted "message_redacted"
  Assert-False $result.credential_values_exposed "credential_values_exposed"
  Assert-False $result.raw_response_included "raw_response_included"
  Assert-False $result.raw_notification_payload_included "raw_notification_payload_included"
  Assert-False $result.token_printed "token_printed"
  return $result
}

$ready = [pscustomobject]@{
  schema = "skybridge.admin_escalation_readiness.v1"
  ok = $true
  primary_current = "hermes-wechat"
  long_term_primary = "skybridge-notify-gateway"
  fallback = "bootstrap-notifier"
  hermes_available = $true
  hermes_direct_https = $true
  hermes_platform = "hermes-agent"
  hermes_runtime_mode = "server_agent"
  hermes_responses_api = $true
  wechat_escalation_configured = $true
  can_send_blocker_notice = $true
  dry_run_supported = $true
  real_send_performed = $false
  credential_values_exposed = $false
  raw_response_included = $false
  token_printed = $false
}

$dryRunFixture = Write-Fixture -Name "dry-run.json" -Value ([pscustomobject]@{
  admin_readiness = $ready
})

$sendSuccessFixture = Join-Path $PSScriptRoot "fixtures\admin-escalation-send-success.json"
if (-not (Test-Path -LiteralPath $sendSuccessFixture -PathType Leaf)) {
  throw "Missing committed send-success fixture."
}

$unsafeResponseFixture = Write-Fixture -Name "unsafe-response.json" -Value ([pscustomobject]@{
  admin_readiness = $ready
  send_endpoint_path = "/v1/admin/escalations/wechat/send"
  send_response = [pscustomobject]@{
    ok = $true
    delivery_status = "sent"
    delivery_confirmed = $true
    credential_values_exposed = $true
    raw_response_included = $true
    raw_notification_payload_included = $true
    token_printed = $false
  }
})

$dryRun = Invoke-AdminTest -ScriptArgs @(
  "-Title", "SkyBridge admin escalation dry run",
  "-Message", "Goal 309 dry-run blocker notification test.",
  "-Severity", "warning",
  "-FixtureFile", $dryRunFixture
)
Assert-True $dryRun.ok "dry-run ok"
Assert-True $dryRun.dry_run "dry-run dry_run"
Assert-False $dryRun.send_requested "dry-run send_requested"
Assert-False $dryRun.send_performed "dry-run send_performed"
Assert-True $dryRun.would_send "dry-run would_send"
if ($dryRun.delivery_status -ne "dry_run") { throw "dry-run delivery_status mismatch." }

$sendSuccess = Invoke-AdminTest -ScriptArgs @(
  "-Title", "SkyBridge admin escalation fixture send",
  "-Message", "Goal 309 fixture send success.",
  "-Severity", "urgent",
  "-Send",
  "-FixtureFile", $sendSuccessFixture
)
Assert-True $sendSuccess.ok "fixture send ok"
Assert-False $sendSuccess.dry_run "fixture send dry_run"
Assert-True $sendSuccess.send_requested "fixture send requested"
Assert-True $sendSuccess.send_performed "fixture send performed"
Assert-True $sendSuccess.delivery_confirmed "fixture send confirmed"
if ($sendSuccess.delivery_status -ne "sent") { throw "fixture send delivery_status mismatch." }

$missingEndpoint = Invoke-AdminTest -ScriptArgs @(
  "-Title", "SkyBridge admin escalation missing endpoint",
  "-Message", "Goal 309 missing endpoint test.",
  "-Severity", "warning",
  "-Send",
  "-FixtureFile", $dryRunFixture
) -AllowFailure
Assert-False $missingEndpoint.ok "missing endpoint ok"
Assert-True $missingEndpoint.send_requested "missing endpoint requested"
Assert-False $missingEndpoint.send_performed "missing endpoint performed"
if ($missingEndpoint.delivery_status -ne "send_endpoint_not_available") { throw "missing endpoint did not report send_endpoint_not_available." }

$unsafeMessage = Invoke-AdminTest -ScriptArgs @(
  "-Title", "SkyBridge admin escalation unsafe message",
  "-Message", "token=secret-value-1234567890",
  "-Severity", "warning",
  "-FixtureFile", $dryRunFixture
) -AllowFailure
Assert-False $unsafeMessage.ok "unsafe message ok"
Assert-False $unsafeMessage.send_performed "unsafe message send_performed"
if ($unsafeMessage.delivery_status -ne "blocked_unsafe_message") { throw "unsafe message was not blocked." }

$unsafeResponse = Invoke-AdminTest -ScriptArgs @(
  "-Title", "SkyBridge admin escalation unsafe response",
  "-Message", "Goal 309 unsafe response fixture.",
  "-Severity", "urgent",
  "-Send",
  "-FixtureFile", $unsafeResponseFixture
) -AllowFailure
Assert-False $unsafeResponse.ok "unsafe response ok"
Assert-False $unsafeResponse.send_performed "unsafe response send_performed"
if ($unsafeResponse.delivery_status -ne "blocked_unsafe_response") { throw "unsafe response was not blocked." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "admin-escalation-test"
  scenarios = @("dry-run-no-send", "fixture-send-success", "missing-endpoint", "credential-exposure-blocks", "safe-output-flags")
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "admin-escalation-test"
}
