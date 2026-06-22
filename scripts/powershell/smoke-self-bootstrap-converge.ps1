[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\self-bootstrap-converge-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Dir, [string]$Name, $Value)
  $path = Join-Path $Dir $Name
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function New-BaseFixtures {
  $commit = "d4b110ebd2973896a913e099e743d81744450da9"
  [pscustomobject]@{
    commit = $commit
    local = [pscustomobject]@{
      branch = "main"
      clean = $true
      head_commit = $commit
      main_commit = $commit
    }
    version = [pscustomobject]@{
      schema = "skybridge.server_version.v1"
      ok = $true
      commit_sha = $commit
      image_ref = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-$commit"
      token_printed = $false
    }
    route = [pscustomobject]@{
      schema = "skybridge.cloud_route_parity.v1"
      ok = $true
      deployment_parity_status = "ok"
      missing_routes = @()
      token_printed = $false
    }
    deploy = [pscustomobject]@{
      schema = "skybridge.cloud_autodeploy_verification.v1"
      ok = $true
      commit_sha = $commit
      version_image_ref = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-$commit"
      deploy_report_status = "succeeded"
      triggered_deploy = $false
      mutated_server = $false
      created_tag = $false
      token_printed = $false
    }
    heartbeat = [pscustomobject]@{
      schema = "skybridge.worker_heartbeat_proof.v1"
      ok = $true
      worker_id = "jerry-win-local-01"
      heartbeat_sent = $true
      worker_online_after = $true
      tasks_claimed = $false
      codex_run_called = $false
      queue_apply_called = $false
      campaign_metadata_advanced = $false
      start_one_called = $false
      run_until_hold_called = $false
      project_control_unpaused = $false
      token_printed = $false
    }
    readiness = [pscustomobject]@{
      schema = "skybridge.self_bootstrap_readiness.v1"
      ok = $true
      status = "partial"
      blockers = @()
      warnings = @("failed_unrecovered_tasks_present", "blocked_tasks_present", "task_evidence_repair_needed", "hermes_server_tool_execution_enabled", "skybridge_notification_center_not_ready")
      can_start_one = $false
      can_run_until_hold = $false
      allow_worker_heartbeat = $true
      allow_start_one = $false
      allow_run_until_hold = $false
      control_plane = [pscustomobject]@{
        project_control = [pscustomobject]@{ state = "paused" }
        workers = [pscustomobject]@{
          online = 1
          online_worker_ids = @("jerry-win-local-01")
        }
      }
      token_printed = $false
    }
    hygiene = [pscustomobject]@{
      schema = "skybridge.task_hygiene_report.v1"
      ok = $true
      total_tasks = 18
      failed_unrecovered = 11
      blocked = 3
      needs_evidence = 1
      stale_leases = 0
      stale_claims = 0
      safe_requeue_candidates = @()
      evidence_repair_candidates = @([pscustomobject]@{ task_id = "remote-docs-exec-pilot-001"; classification = "evidence-repair-only" })
      archive_or_keep_blocked_candidates = @(
        [pscustomobject]@{ task_id = "always-on-worker-loop-pilot-docs-179"; classification = "historical-residue" },
        [pscustomobject]@{ task_id = "task_proposal-59a0236fb69800cd"; classification = "historical-residue" },
        [pscustomobject]@{ task_id = "remote-claim-smoke-001"; classification = "historical-residue" }
      )
      unsafe_to_requeue_candidates = @(1..11 | ForEach-Object { [pscustomobject]@{ task_id = "unsafe-to-requeue-$($_)"; classification = "unsafe-to-requeue" } })
      task_classifications = @()
      safety = [pscustomobject]@{
        tasks_mutated = $false
        tasks_claimed = $false
        tasks_requeued = $false
        tasks_cancelled = $false
        evidence_written = $false
        codex_run_called = $false
        queue_apply_called = $false
        campaign_metadata_advanced = $false
        project_control_unpaused = $false
        token_printed = $false
      }
      token_printed = $false
    }
    hygieneApply = [pscustomobject]@{
      schema = "skybridge.task_hygiene_apply.v1"
      ok = $true
      mode = "preview"
      planned_actions = [pscustomobject]@{
        evidence_repair_actions = @([pscustomobject]@{ task_id = "remote-docs-exec-pilot-001"; operation = "mark_evidence_repair_applied" })
        archive_or_keep_blocked_actions = @(
          [pscustomobject]@{ task_id = "always-on-worker-loop-pilot-docs-179"; operation = "mark_keep_blocked" },
          [pscustomobject]@{ task_id = "task_proposal-59a0236fb69800cd"; operation = "mark_keep_blocked" },
          [pscustomobject]@{ task_id = "remote-claim-smoke-001"; operation = "mark_keep_blocked" }
        )
        unsafe_to_requeue_exclusion_actions = @(1..11 | ForEach-Object { [pscustomobject]@{ task_id = "unsafe-to-requeue-$($_)"; operation = "mark_excluded_from_requeue" } })
      }
      residual_warnings = @("preview_only_no_task_mutation")
      recommended_next_safe_action = "Review preview only."
      safety = [pscustomobject]@{
        preview_only = $true
        tasks_claimed = $false
        tasks_requeued = $false
        codex_run_called = $false
        project_control_unpaused = $false
        start_one_called = $false
        run_until_hold_called = $false
        token_printed = $false
      }
      token_printed = $false
    }
    notification = [pscustomobject]@{
      schema = "skybridge.notification_readiness.v1"
      ok = $true
      status = "partial"
      dry_run = $true
      provider_count = 2
      ready_provider_count = 1
      real_provider_count = 2
      real_ready_provider_count = 1
      dry_run_safe_provider_count = 1
      provider_configuration_status = "real_provider_ready"
      bootstrap_dry_run_available = $true
      blocker_notice_supported = $true
      real_send_performed = $false
      raw_notification_payload_included = $false
      credential_values_exposed = $false
      token_printed = $false
    }
    executionSecondGate = [pscustomobject]@{
      schema = "skybridge.execution_second_gate_readiness.v1"
      ok = $true
      status = "preview_ready"
      project_id = "skybridge-agent-hub"
      project_control_state = "paused"
      cloud_commit_aligned = $true
      worker_online = $true
      notification_blocker_notice_supported = $true
      hermes_exposure_status = "blocked"
      hermes_tool_execution_risk = $true
      second_gate_configured = $false
      allowed_preview_only = $true
      allowed_execution = $false
      preview_blockers = @()
      token_printed = $false
    }
    startOnePreview = [pscustomobject]@{
      schema = "skybridge.start_one_preview.v1"
      ok = $true
      status = "no_safe_candidate"
      preview_only = $true
      would_claim = $false
      would_run_codex = $false
      would_unpause_project_control = $false
      selected_candidate = $null
      candidate_pool_summary = [pscustomobject]@{ total_tasks = 18; queued_tasks = 0; eligible_candidates = 0; excluded_tasks = 15; online_workers = 1 }
      excluded_tasks_summary = [pscustomobject]@{
        failed_tasks_excluded = 12
        blocked_historical_tasks_excluded = 3
        hygiene_metadata_excluded_tasks = 12
        unsafe_to_requeue_tasks_excluded = 12
        completed_tasks_excluded = 3
        remote_docs_exec_pilot_001_excluded = $true
        goal_315_317_residue_eligible = 0
      }
      token_printed = $false
    }
  }
}

function Invoke-ConvergeFixture {
  param([string]$Name, [scriptblock]$Mutate, [switch]$RefreshHeartbeat)
  $dir = Join-Path $tmpRoot $Name
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $fixtures = New-BaseFixtures
  if ($Mutate) { & $Mutate $fixtures }

  $localPath = Write-Fixture $dir "local.json" $fixtures.local
  $versionPath = Write-Fixture $dir "version.json" $fixtures.version
  $routePath = Write-Fixture $dir "route.json" $fixtures.route
  $deployPath = Write-Fixture $dir "deploy.json" $fixtures.deploy
  $heartbeatPath = Write-Fixture $dir "heartbeat.json" $fixtures.heartbeat
  $readinessPath = Write-Fixture $dir "readiness.json" $fixtures.readiness
  $hygienePath = Write-Fixture $dir "hygiene.json" $fixtures.hygiene
  $hygieneApplyPath = Write-Fixture $dir "hygiene-apply.json" $fixtures.hygieneApply
  $notificationPath = Write-Fixture $dir "notification-readiness.json" $fixtures.notification
  $executionSecondGatePath = Write-Fixture $dir "execution-second-gate.json" $fixtures.executionSecondGate
  $startOnePreviewPath = Write-Fixture $dir "start-one-preview.json" $fixtures.startOnePreview

  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "skybridge-self-bootstrap-converge.ps1"),
    "-ApiBase", "https://skybridge.fixture",
    "-ProjectId", "skybridge-agent-hub",
    "-FixtureLocalFile", $localPath,
    "-FixtureVersionFile", $versionPath,
    "-FixtureRouteParityFile", $routePath,
    "-FixtureDeployEvidenceFile", $deployPath,
    "-FixtureHeartbeatFile", $heartbeatPath,
    "-FixtureReadinessFile", $readinessPath,
    "-FixtureHygieneFile", $hygienePath,
    "-FixtureHygieneApplyFile", $hygieneApplyPath,
    "-FixtureNotificationReadinessFile", $notificationPath,
    "-FixtureExecutionSecondGateFile", $executionSecondGatePath,
    "-FixtureStartOnePreviewFile", $startOnePreviewPath,
    "-Json"
  )
  if ($RefreshHeartbeat) { $args += "-RefreshHeartbeat" }

  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "convergence script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.self_bootstrap_convergence.v1") { throw "Unexpected convergence schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  return [pscustomobject]@{ name = $Name; result = $result; text = $text }
}

function Assert-Contains {
  param($Values, [string]$Expected, [string]$Name)
  if (@($Values) -notcontains $Expected) { throw "$Name missing expected value '$Expected'." }
}

$cases = @()

$case = Invoke-ConvergeFixture -Name "not-on-main" -Mutate { param($f) $f.local.branch = "codex/goal-316" }
if ($case.result.status -ne "partial") { throw "not-on-main should defer execution but keep preview convergence partial." }
Assert-Contains $case.result.deferred_execution_blockers "not_on_main" "not-on-main deferred blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "cloud-mismatch" -Mutate { param($f) $f.version.commit_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
if ($case.result.status -ne "blocked") { throw "cloud-mismatch should block." }
Assert-Contains $case.result.blocked_reasons "cloud_commit_mismatch" "cloud-mismatch blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "partial-with-warnings" -Mutate {}
if ($case.result.status -ne "partial") { throw "warnings fixture should be partial." }
Assert-True $case.result.ok "partial ok"
if (@($case.result.blocked_reasons).Count -ne 0) { throw "partial fixture should not have convergence blockers." }
Assert-True $case.result.cloud.commit_aligned "partial commit aligned"
Assert-False $case.result.readiness.can_start_one "partial can_start_one"
Assert-False $case.result.readiness.can_run_until_hold "partial can_run_until_hold"
Assert-True $case.result.hygiene_apply_preview.available "partial hygiene_apply_preview available"
if ($case.result.hygiene_apply_preview.mode -ne "preview") { throw "Expected hygiene apply preview mode." }
if ($case.result.hygiene_apply_preview.evidence_repair_actions_count -ne 1) { throw "Expected one hygiene apply evidence action." }
if ($case.result.hygiene_apply_preview.archive_or_keep_blocked_actions_count -ne 3) { throw "Expected three hygiene apply blocked actions." }
if ($case.result.hygiene_apply_preview.unsafe_to_requeue_exclusion_actions_count -ne 11) { throw "Expected eleven hygiene apply exclusion actions." }
Assert-True $case.result.notification_readiness.available "partial notification_readiness available"
Assert-True $case.result.notification_readiness.dry_run "partial notification dry_run"
Assert-False $case.result.notification_readiness.real_send_performed "partial notification real_send_performed"
Assert-False $case.result.notification_readiness.credential_values_exposed "partial notification credential_values_exposed"
Assert-True $case.result.execution_second_gate.available "partial execution_second_gate available"
if ($case.result.execution_second_gate.status -ne "preview_ready") { throw "Expected execution second gate preview_ready." }
Assert-True $case.result.execution_second_gate.allowed_preview_only "partial execution second gate preview"
Assert-False $case.result.execution_second_gate.allowed_execution "partial execution second gate execution"
Assert-True $case.result.execution_forbidden "partial execution forbidden"
if ($case.result.can_start_one_false_reason -ne "self_bootstrap_readiness_can_start_one_false") { throw "Unexpected can_start_one_false_reason." }
Assert-True $case.result.start_one_preview.available "partial start_one_preview available"
if ($case.result.start_one_preview.status -ne "no_safe_candidate") { throw "Expected start_one_preview no_safe_candidate." }
if ($null -ne $case.result.start_one_preview.selected_candidate) { throw "Expected no selected candidate." }
Assert-False $case.result.start_one_preview.would_claim "start_one_preview would_claim"
Assert-False $case.result.start_one_preview.would_run_codex "start_one_preview would_run_codex"
$cases += $case

$case = Invoke-ConvergeFixture -Name "active-non-pilot-blocks" -Mutate {
  param($f)
  $f.readiness.blockers = @("active_tasks_present")
}
if ($case.result.status -ne "blocked") { throw "active non-pilot task should remain a blocker." }
Assert-Contains $case.result.blocked_reasons "active_tasks_present" "active non-pilot blockers"
Assert-False $case.result.hygiene.active_task_allowed_for_goal_319_pilot "active non-pilot allowed flag"
$cases += $case

$case = Invoke-ConvergeFixture -Name "expected-active-pilot-allowed" -Mutate {
  param($f)
  $f.readiness.blockers = @("active_tasks_present")
  $f.hygiene.total_tasks = 19
  $f.hygiene.task_classifications = @(
    [pscustomobject]@{
      task_id = "start-one-apply-pilot-docs-001"
      status = "queued"
      hygiene_status = "active_ok"
      classification = "not-residue"
      risk = "not_reported"
      task_type = "docs"
      assigned_worker_id = "-"
      recommended_action = "No Goal 315 action."
    }
  )
  $f.startOnePreview.status = "candidate_previewed"
  $f.startOnePreview.selected_candidate = [pscustomobject]@{ task_id = "start-one-apply-pilot-docs-001" }
}
if ($case.result.status -ne "partial") { throw "expected active pilot should not block convergence." }
if (@($case.result.blocked_reasons) -contains "active_tasks_present") { throw "Expected pilot active task was treated as generic active blocker." }
Assert-True $case.result.hygiene.expected_active_pilot_task "expected active pilot flag"
if ($case.result.hygiene.active_task_id -ne "start-one-apply-pilot-docs-001") { throw "Expected active pilot task id." }
Assert-True $case.result.hygiene.active_task_allowed_for_goal_319_pilot "active pilot allowed flag"
$cases += $case

$case = Invoke-ConvergeFixture -Name "bootstrap-notification-only" -Mutate {
  param($f)
  $f.readiness.warnings = @("admin_escalation_bootstrap_dry_run_only", "skybridge_notification_center_not_ready")
  $f.notification = [pscustomobject]@{
    schema = "skybridge.notification_readiness.v1"
    ok = $true
    status = "partial"
    dry_run = $true
    provider_count = 1
    ready_provider_count = 1
    real_provider_count = 0
    real_ready_provider_count = 0
    dry_run_safe_provider_count = 1
    provider_configuration_status = "no_provider_configured_bootstrap_dry_run_available"
    bootstrap_dry_run_available = $true
    blocker_notice_supported = $true
    real_send_performed = $false
    raw_notification_payload_included = $false
    credential_values_exposed = $false
    token_printed = $false
  }
}
if ($case.result.status -ne "partial") { throw "bootstrap notification fixture should be partial." }
Assert-True $case.result.notification_readiness.blocker_notice_supported "bootstrap notification blocker_notice_supported"
Assert-False $case.result.notification_readiness.real_send_performed "bootstrap notification real_send_performed"
Assert-False $case.result.notification_readiness.raw_notification_payload_included "bootstrap notification raw_notification_payload_included"
Assert-False $case.result.notification_readiness.credential_values_exposed "bootstrap notification credential_values_exposed"
if (@($case.result.readiness.blockers) -contains "admin_escalation_unavailable") { throw "bootstrap notification fixture must not report admin_escalation_unavailable." }
if (@($case.result.blocked_reasons) -contains "admin_escalation_unavailable") { throw "bootstrap notification fixture must not block on admin_escalation_unavailable." }
$cases += $case

$case = Invoke-ConvergeFixture -Name "heartbeat-fails" -RefreshHeartbeat -Mutate {
  param($f)
  $f.heartbeat.ok = $false
  $f.heartbeat.heartbeat_sent = $false
  $f.heartbeat.worker_online_after = $false
}
if ($case.result.status -ne "blocked") { throw "heartbeat failure should block." }
Assert-Contains $case.result.blocked_reasons "heartbeat_refresh_failed" "heartbeat failure blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "heartbeat-unsafe-flag" -RefreshHeartbeat -Mutate {
  param($f)
  $f.heartbeat.tasks_claimed = $true
}
if ($case.result.status -ne "blocked") { throw "unsafe heartbeat flag should block." }
Assert-True $case.result.heartbeat.tasks_claimed "heartbeat tasks_claimed passthrough"
Assert-Contains $case.result.blocked_reasons "unsafe_mutation_flag_detected" "heartbeat unsafe blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "deploy-unsafe-flag" -Mutate { param($f) $f.deploy.mutated_server = $true }
if ($case.result.status -ne "blocked") { throw "unsafe deploy mutation flag should block." }
Assert-Contains $case.result.blocked_reasons "unsafe_mutation_flag_detected" "deploy unsafe blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "readiness-unavailable" -Mutate {
  param($f)
  $f.readiness = [pscustomobject]@{
    ok = $false
    error_summary = "fixture unavailable"
    token_printed = $false
  }
}
if ($case.result.status -ne "blocked") { throw "readiness unavailable should block." }
Assert-Contains $case.result.blocked_reasons "self_bootstrap_readiness_unavailable" "readiness unavailable blockers"
$cases += $case

$case = Invoke-ConvergeFixture -Name "hygiene-unavailable" -Mutate {
  param($f)
  $f.hygiene = [pscustomobject]@{
    ok = $false
    error_summary = "fixture unavailable"
    token_printed = $false
  }
}
if ($case.result.status -ne "blocked") { throw "hygiene unavailable should block." }
Assert-Contains $case.result.blocked_reasons "task_hygiene_report_unavailable" "hygiene unavailable blockers"
$cases += $case

$summary = [pscustomobject]@{
  ok = $true
  smoke = "self-bootstrap-converge"
  scenarios = @($cases | ForEach-Object { [pscustomobject]@{ name = $_.name; status = $_.result.status; token_printed = $false } })
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "self-bootstrap-converge"
}
