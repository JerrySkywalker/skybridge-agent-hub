[CmdletBinding()]
param(
  [ValidateSet("all", "ready", "worker-offline", "stale-leases", "hermes-unavailable", "no-secrets")]
  [string]$Scenario = "all",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\self-bootstrap-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Dir, [string]$Name, $Value)
  $path = Join-Path $Dir $Name
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function New-BaseFixtures {
  param([string]$Dir)
  $commit = "8a8fd187e70b6931ec058b07f4867c033431c618"
  $imageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-$commit"
  $git = [pscustomobject]@{
    branch = "main"
    clean = $true
    head_commit = $commit
    main_ref = "origin/main"
    main_commit = $commit
  }
  $version = [pscustomobject]@{
    schema = "skybridge.server_version.v1"
    commit_sha = $commit
    image_tag = "sha-$commit"
    image_ref = $imageRef
    token_printed = $false
  }
  $parity = [pscustomobject]@{
    schema = "skybridge.cloud_route_parity.v1"
    ok = $true
    deployment_parity_status = "ok"
    server_online = $true
    manual_task_routes_available = $true
    missing_routes = @()
    recommended_action = "Cloud route parity ok."
    token_printed = $false
  }
  $deploy = [pscustomobject]@{
    ok = $true
    schema = "skybridge.cloud_autodeploy_verification.v1"
    repo = "JerrySkywalker/skybridge-agent-hub"
    commit_sha = $commit
    docker_images_run_id = 307001
    deploy_cloud_run_id = 307002
    deploy_report_status = "succeeded"
    deploy_report_reason = "deployed"
    cloud_parity_status = "ok"
    version_commit_sha = $commit
    version_image_ref = $imageRef
    rollback_status = "not_used"
    token_printed = $false
    mutated_server = $false
    triggered_deploy = $false
    created_tag = $false
  }
  $status = [pscustomobject]@{
    ok = $true
    project_id = "skybridge-agent-hub"
    token_printed = $false
    control_summary = [pscustomobject]@{
      state = "paused"
      stop_requested = $false
      stop_reason = $null
      degraded_reason = $null
    }
    task_summary = [pscustomobject]@{
      total = 0
      active = 0
      queued = 0
      claimed = 0
      running = 0
      stale_leases = 0
      stale_claims = 0
      stale_running = 0
      missing_leases = 0
      failed_unrecovered = 0
      blocked = 0
      needs_evidence = 0
    }
    workers = @(
      [pscustomobject]@{
        worker_id = "laptop-zenbookduo"
        status = "online"
        last_seen_at = "2026-06-18T00:00:00Z"
        current_task_id = $null
      }
    )
    campaign_summary = [pscustomobject]@{
      total = 1
      ready = 1
      running = 0
      paused = 0
      held = 0
      failed = 0
      completed = 0
      aborted = 0
    }
    warnings = @()
  }
  $hermes = [pscustomobject]@{
    ok = $true
    api_base = "https://api.hermes.fixture"
    direct_https = $true
    platform = "hermes-agent"
    model = "fixture"
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
  $notifications = [pscustomobject]@{
    providers = @(
      [pscustomobject]@{
        provider = "ntfy"
        status = "ok"
        credential_values_exposed = $false
      },
      [pscustomobject]@{
        provider = "gotify"
        status = "skipped"
        credential_values_exposed = $false
      }
    )
  }

  [pscustomobject]@{
    commit = $commit
    git = $git
    version = $version
    parity = $parity
    deploy = $deploy
    status = $status
    hermes = $hermes
    notifications = $notifications
  }
}

function Invoke-ReadinessFixture {
  param([string]$Name, [scriptblock]$Mutate)
  $dir = Join-Path $tmpRoot $Name
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $fixtures = New-BaseFixtures -Dir $dir
  if ($Mutate) { & $Mutate $fixtures }

  $gitPath = Write-Fixture -Dir $dir -Name "git.json" -Value $fixtures.git
  $versionPath = Write-Fixture -Dir $dir -Name "version.json" -Value $fixtures.version
  $parityPath = Write-Fixture -Dir $dir -Name "parity.json" -Value $fixtures.parity
  $deployPath = Write-Fixture -Dir $dir -Name "deploy.json" -Value $fixtures.deploy
  $statusPath = Write-Fixture -Dir $dir -Name "status.json" -Value $fixtures.status
  $hermesPath = Write-Fixture -Dir $dir -Name "hermes.json" -Value $fixtures.hermes
  $notificationsPath = Write-Fixture -Dir $dir -Name "notifications.json" -Value $fixtures.notifications

  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-self-bootstrap-readiness.ps1") `
    -ApiBase "https://skybridge.fixture" `
    -ProjectId "skybridge-agent-hub" `
    -FixtureGitFile $gitPath `
    -FixtureVersionFile $versionPath `
    -FixtureParityFile $parityPath `
    -FixtureDeployEvidenceFile $deployPath `
    -FixtureStatusFile $statusPath `
    -FixtureHermesHealthFile $hermesPath `
    -FixtureNotificationsFile $notificationsPath `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "readiness script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  Assert-True $result.ok "placeholder"
  if ($result.schema -ne "skybridge.self_bootstrap_readiness.v1") { throw "Unexpected schema for $Name." }
  Assert-False $result.token_printed "token_printed"
  Assert-False $result.safety.codex_run_called "codex_run_called"
  Assert-False $result.safety.queue_apply_called "queue_apply_called"
  Assert-False $result.safety.campaign_metadata_advanced "campaign_metadata_advanced"
  Assert-False $result.safety.deploy_triggered "deploy_triggered"
  Assert-False $result.safety.tag_or_release_created "tag_or_release_created"
  return [pscustomobject]@{
    name = $Name
    result = $result
    text = $text
  }
}

function Assert-Contains {
  param($Values, [string]$Expected, [string]$Name)
  if (@($Values) -notcontains $Expected) { throw "$Name missing expected value '$Expected'." }
}

function Invoke-Scenario {
  param([string]$Name)
  switch ($Name) {
    "ready" {
      $case = Invoke-ReadinessFixture -Name $Name -Mutate {}
      if ($case.result.status -ne "ready") { throw "ready fixture should be ready." }
      Assert-True $case.result.can_start_one "can_start_one"
      Assert-True $case.result.can_run_until_hold "can_run_until_hold"
      if (@($case.result.blockers).Count -ne 0) { throw "ready fixture should have no blockers." }
    }
    "worker-offline" {
      $case = Invoke-ReadinessFixture -Name $Name -Mutate {
        param($fixtures)
        $fixtures.status.workers = @([pscustomobject]@{ worker_id = "laptop-zenbookduo"; status = "offline"; last_seen_at = "2026-06-17T00:00:00Z"; current_task_id = $null })
      }
      if ($case.result.status -ne "blocked") { throw "worker-offline fixture should be blocked." }
      Assert-Contains $case.result.blockers "worker_offline" "worker-offline blockers"
      Assert-False $case.result.can_start_one "worker-offline can_start_one"
    }
    "stale-leases" {
      $case = Invoke-ReadinessFixture -Name $Name -Mutate {
        param($fixtures)
        $fixtures.status.task_summary.stale_leases = 1
      }
      if ($case.result.status -ne "blocked") { throw "stale-leases fixture should be blocked." }
      Assert-Contains $case.result.blockers "stale_leases_present" "stale-leases blockers"
      Assert-False $case.result.can_run_until_hold "stale-leases can_run_until_hold"
    }
    "hermes-unavailable" {
      $case = Invoke-ReadinessFixture -Name $Name -Mutate {
        param($fixtures)
        $fixtures.hermes.ok = $false
      }
      if ($case.result.status -ne "blocked") { throw "hermes-unavailable fixture should be blocked." }
      Assert-Contains $case.result.blockers "hermes_unavailable" "hermes-unavailable blockers"
      Assert-False $case.result.can_run_until_hold "hermes-unavailable can_run_until_hold"
    }
    "no-secrets" {
      $case = Invoke-ReadinessFixture -Name $Name -Mutate {
        param($fixtures)
        $fixtures.hermes.api_base = "https://api.hermes.fixture/v1?token=sk-THIS_SHOULD_NOT_APPEAR_1234567890"
        $fixtures.status.warnings = @("authorization: bearer abcdefghijklmnopqrstuvwxyz123456")
        $fixtures.notifications.providers += [pscustomobject]@{
          provider = "fixture-secret-provider"
          status = "skipped"
          credential_values_exposed = $false
          raw_token = "ghp_THIS_SHOULD_NOT_APPEAR_1234567890"
        }
      }
      Assert-False $case.result.token_printed "no-secrets token_printed"
      Assert-NoUnsafeText $case.text
      if ($case.text -match "THIS_SHOULD_NOT_APPEAR") { throw "Secret marker leaked in no-secrets fixture." }
      if ($case.result.hermes.endpoint -ne "https://[redacted-host]") { throw "Hermes endpoint was not redacted." }
    }
    default {
      throw "Unknown scenario: $Name"
    }
  }
  [pscustomobject]@{ ok = $true; scenario = $Name; token_printed = $false }
}

$scenarioNames = if ($Scenario -eq "all") {
  @("ready", "worker-offline", "stale-leases", "hermes-unavailable", "no-secrets")
} else {
  @($Scenario)
}

$results = @()
foreach ($name in $scenarioNames) {
  $results += Invoke-Scenario -Name $name
}

$summary = [pscustomobject]@{
  ok = $true
  smoke = "self-bootstrap-readiness"
  scenarios = @($results)
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 10 -Compress
} else {
  Complete-Smoke "self-bootstrap-readiness"
}
