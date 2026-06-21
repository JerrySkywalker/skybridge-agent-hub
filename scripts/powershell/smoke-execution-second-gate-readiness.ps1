[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\execution-second-gate-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-Gate {
  param([string]$Name, $Readiness, $Hermes, $Notification)
  $readinessPath = Write-Fixture "$Name-readiness.json" $Readiness
  $hermesPath = Write-Fixture "$Name-hermes.json" $Hermes
  $notificationPath = Write-Fixture "$Name-notification.json" $Notification
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-execution-second-gate-readiness.ps1 `
    -ProjectId "skybridge-agent-hub" `
    -FixtureReadinessFile $readinessPath `
    -FixtureHermesExposureFile $hermesPath `
    -FixtureNotificationReadinessFile $notificationPath `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "execution second gate script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.execution_second_gate_readiness.v1") { throw "Unexpected schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  return $result
}

$commit = "d343218bbf23c098d30e3a3e06aded95de4853f3"
$baseReadiness = [pscustomobject]@{
  schema = "skybridge.self_bootstrap_readiness.v1"
  ok = $true
  status = "partial"
  can_start_one = $false
  can_run_until_hold = $false
  repo = [pscustomobject]@{ main_commit = $commit }
  cloud = [pscustomobject]@{
    version = [pscustomobject]@{ commit_sha = $commit; token_printed = $false }
    deploy_evidence = [pscustomobject]@{ ok = $true; token_printed = $false }
  }
  control_plane = [pscustomobject]@{
    project_control = [pscustomobject]@{ state = "paused" }
    workers = [pscustomobject]@{ online = 1 }
  }
  token_printed = $false
}
$baseNotification = [pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = $true
  status = "partial"
  blocker_notice_supported = $true
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
}
$serverToolNoGate = [pscustomobject]@{
  schema = "skybridge.hermes_exposure_readiness.v1"
  ok = $false
  status = "blocked"
  risk_level = "high"
  blockers = @("hermes_second_gate_required_for_server_tool_execution")
  warnings = @("hermes_server_tool_execution_enabled")
  hermes = [pscustomobject]@{ tool_execution = "server"; token_printed = $false }
  second_gate = [pscustomobject]@{ configured = $false; token_printed = $false }
  safety = [pscustomobject]@{ read_only = $true; token_printed = $false }
  token_printed = $false
}
$serverToolWithGate = [pscustomobject]@{
  schema = "skybridge.hermes_exposure_readiness.v1"
  ok = $true
  status = "warning"
  risk_level = "high"
  blockers = @()
  warnings = @("hermes_server_tool_execution_enabled")
  hermes = [pscustomobject]@{ tool_execution = "server"; token_printed = $false }
  second_gate = [pscustomobject]@{ configured = $true; token_printed = $false }
  safety = [pscustomobject]@{ read_only = $true; token_printed = $false }
  token_printed = $false
}

$previewOnly = Invoke-Gate -Name "preview-only" -Readiness $baseReadiness -Hermes $serverToolNoGate -Notification $baseNotification
if ($previewOnly.status -ne "preview_ready") { throw "Expected preview_ready when only execution is blocked." }
Assert-True $previewOnly.allowed_preview_only "preview allowed"
Assert-False $previewOnly.allowed_execution "execution allowed"
if ($previewOnly.project_control_state -ne "paused") { throw "Expected paused project control." }
Assert-True $previewOnly.hermes_tool_execution_risk "Hermes tool execution risk"
Assert-False $previewOnly.second_gate_configured "second gate configured"
Assert-False $previewOnly.forbidden_actions.start_one_called "start_one_called"
Assert-False $previewOnly.forbidden_actions.run_until_hold_called "run_until_hold_called"

$stillPaused = Invoke-Gate -Name "second-gated-paused" -Readiness $baseReadiness -Hermes $serverToolWithGate -Notification $baseNotification
Assert-True $stillPaused.allowed_preview_only "second-gated preview allowed"
Assert-False $stillPaused.allowed_execution "second-gated paused execution"
if ($stillPaused.status -ne "preview_ready") { throw "Paused project control must keep status preview_ready." }

$blockedReadiness = $baseReadiness | ConvertTo-Json -Depth 24 | ConvertFrom-Json
$blockedReadiness.control_plane.project_control.state = "running"
$blocked = Invoke-Gate -Name "control-running" -Readiness $blockedReadiness -Hermes $serverToolWithGate -Notification $baseNotification
if ($blocked.status -ne "blocked") { throw "Project control running should block preview." }
if (@($blocked.preview_blockers) -notcontains "project_control_not_paused") { throw "Expected project_control_not_paused blocker." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "execution-second-gate-readiness"
  scenarios = @(
    [pscustomobject]@{ name = "server_tool_execution_blocks_execution"; status = $previewOnly.status; allowed_execution = $previewOnly.allowed_execution },
    [pscustomobject]@{ name = "preview_only_allowed_while_paused"; status = $stillPaused.status; allowed_preview_only = $stillPaused.allowed_preview_only },
    [pscustomobject]@{ name = "project_control_running_blocks_preview"; status = $blocked.status }
  )
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "execution-second-gate-readiness"
}
