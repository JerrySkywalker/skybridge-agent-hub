[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\admin-escalation-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-AdminProbe {
  param([string[]]$ScriptArgs)
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-admin-escalation-readiness.ps1") @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "admin escalation readiness probe failed." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.admin_escalation_readiness.v1") { throw "Unexpected admin escalation readiness schema." }
  Assert-False $result.real_send_performed "real_send_performed"
  Assert-False $result.credential_values_exposed "credential_values_exposed"
  Assert-False $result.raw_response_included "raw_response_included"
  Assert-False $result.token_printed "token_printed"
  return $result
}

$readyFixture = [pscustomobject]@{
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

$hermesFixture = [pscustomobject]@{
  ok = $true
  api_base = "https://api.hermes.fixture"
  direct_https = $true
  platform = "hermes-agent"
  runtime = [pscustomobject]@{
    mode = "server_agent"
    tool_execution = "disabled"
  }
  features = [pscustomobject]@{
    responses_api = $true
    runs = $true
  }
  token_printed = $false
}

$readyPath = Write-Fixture -Name "ready-admin-escalation.json" -Value $readyFixture
$hermesPath = Write-Fixture -Name "hermes-health.json" -Value $hermesFixture

$ready = Invoke-AdminProbe -ScriptArgs @("-FixtureFile", $readyPath)
Assert-True $ready.ok "fixture ready ok"
Assert-True $ready.can_send_blocker_notice "fixture can_send_blocker_notice"
if ($ready.primary_current -ne "hermes-wechat") { throw "primary_current must be hermes-wechat." }
if ($ready.long_term_primary -ne "skybridge-notify-gateway") { throw "long_term_primary must be skybridge-notify-gateway." }
if ($ready.fallback -ne "bootstrap-notifier") { throw "fallback must be bootstrap-notifier." }

$previousConfigured = [Environment]::GetEnvironmentVariable("SKYBRIDGE_ADMIN_ESCALATION_WECHAT_CONFIGURED", "Process")
try {
  [Environment]::SetEnvironmentVariable("SKYBRIDGE_ADMIN_ESCALATION_WECHAT_CONFIGURED", "true", "Process")
  $dryRun = Invoke-AdminProbe -ScriptArgs @("-FixtureHermesHealthFile", $hermesPath)
  Assert-True $dryRun.ok "dry-run ok"
  Assert-True $dryRun.dry_run_supported "dry_run_supported"
  Assert-True $dryRun.wechat_escalation_configured "wechat_escalation_configured"
} finally {
  [Environment]::SetEnvironmentVariable("SKYBRIDGE_ADMIN_ESCALATION_WECHAT_CONFIGURED", $previousConfigured, "Process")
}

$summary = [pscustomobject]@{
  ok = $true
  smoke = "admin-escalation-readiness"
  scenarios = @("fixture-ready", "default-no-send")
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "admin-escalation-readiness"
}
