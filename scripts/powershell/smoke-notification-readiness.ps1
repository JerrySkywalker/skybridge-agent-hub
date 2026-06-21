[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\notification-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$fixturePath = Join-Path $tmpRoot "providers.json"
$bootstrapOnlyFixturePath = Join-Path $tmpRoot "providers-bootstrap-only.json"

[pscustomobject]@{
  providers = @(
    [pscustomobject]@{ provider = "ntfy"; status = "skipped"; configured = $false; credential_values_exposed = $false },
    [pscustomobject]@{ provider = "wecom"; status = "ready"; configured = $true; credential_values_exposed = $false }
  )
  summary = [pscustomobject]@{ total = 0; sent = 0; skipped = 0; failed = 0 }
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $fixturePath -Encoding UTF8

[pscustomobject]@{
  providers = @()
  summary = [pscustomobject]@{ total = 0; sent = 0; skipped = 0; failed = 0 }
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $bootstrapOnlyFixturePath -Encoding UTF8

$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-notification-readiness.ps1") `
  -FixtureProvidersFile $fixturePath `
  -DryRun `
  -Json
if ($LASTEXITCODE -ne 0) { throw "notification readiness script failed." }
$text = (($raw | Out-String).Trim())
Assert-NoUnsafeText $text
if ($text -match "raw_notification_payload_secret|webhook://|cookie\s*[:=]|fixture raw prompt|fixture raw log") { throw "Unsafe notification text leaked." }
$result = $text | ConvertFrom-Json

if ($result.schema -ne "skybridge.notification_readiness.v1") { throw "Unexpected notification readiness schema." }
Assert-True $result.ok "ok"
Assert-True $result.dry_run "dry_run"
if ($result.status -ne "partial") { throw "Expected partial notification readiness." }
Assert-True $result.blocker_notice_supported "blocker_notice_supported"
Assert-False $result.real_send_performed "real_send_performed"
Assert-False $result.raw_notification_payload_included "raw_notification_payload_included"
Assert-False $result.credential_values_exposed "credential_values_exposed"
Assert-False $result.token_printed "token_printed"
if ($result.real_provider_count -ne 2) { throw "Expected two real provider summaries." }
if (@($result.providers).Count -ne 3) { throw "Expected two real providers plus bootstrap dry-run summary." }
if ($result.dry_run_safe_provider_count -lt 1) { throw "Expected a dry-run-safe provider summary." }
foreach ($provider in @($result.providers)) {
  Assert-True $provider.dry_run_checked "provider dry_run_checked"
  Assert-False $provider.raw_notification_payload_included "provider raw_notification_payload_included"
  Assert-False $provider.credential_values_exposed "provider credential_values_exposed"
}

$bootstrapRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-notification-readiness.ps1") `
  -FixtureProvidersFile $bootstrapOnlyFixturePath `
  -DryRun `
  -Json
if ($LASTEXITCODE -ne 0) { throw "notification readiness bootstrap-only script failed." }
$bootstrapText = (($bootstrapRaw | Out-String).Trim())
Assert-NoUnsafeText $bootstrapText
if ($bootstrapText -match "raw_notification_payload_secret|webhook://|cookie\s*[:=]|fixture raw prompt|fixture raw log") { throw "Unsafe bootstrap notification text leaked." }
$bootstrap = $bootstrapText | ConvertFrom-Json

if ($bootstrap.schema -ne "skybridge.notification_readiness.v1") { throw "Unexpected bootstrap notification readiness schema." }
Assert-True $bootstrap.ok "bootstrap ok"
Assert-True $bootstrap.dry_run "bootstrap dry_run"
if ($bootstrap.status -ne "partial") { throw "Expected partial bootstrap notification readiness." }
if ($bootstrap.provider_configuration_status -ne "no_provider_configured_bootstrap_dry_run_available") { throw "Expected bootstrap no-provider status." }
Assert-True $bootstrap.bootstrap_dry_run_available "bootstrap_dry_run_available"
Assert-True $bootstrap.blocker_notice_supported "bootstrap blocker_notice_supported"
if ($bootstrap.real_provider_count -ne 0) { throw "Expected zero real providers." }
if ($bootstrap.real_ready_provider_count -ne 0) { throw "Expected zero real ready providers." }
if ($bootstrap.dry_run_safe_provider_count -lt 1) { throw "Expected at least one dry-run-safe provider." }
Assert-False $bootstrap.real_send_performed "bootstrap real_send_performed"
Assert-False $bootstrap.raw_notification_payload_included "bootstrap raw_notification_payload_included"
Assert-False $bootstrap.credential_values_exposed "bootstrap credential_values_exposed"
Assert-False $bootstrap.token_printed "bootstrap token_printed"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "notification-readiness"
  status = $result.status
  bootstrap_status = $bootstrap.status
  dry_run = $true
  real_send_performed = $false
  token_printed = $false
}
if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "notification-readiness"
}
