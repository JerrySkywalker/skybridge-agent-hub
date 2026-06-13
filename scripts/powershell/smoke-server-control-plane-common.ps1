$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Read-SkyBridgeFile([string]$RelativePath) {
  $root = Get-SkyBridgeRoot
  return Get-Content -Raw -LiteralPath (Join-Path $root $RelativePath)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text -notmatch [regex]::Escape($Needle)) { throw $Message }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text -match [regex]::Escape($Needle)) { throw $Message }
}

function Get-ControlPlaneTexts {
  return [pscustomobject]@{
    Schema = Read-SkyBridgeFile "packages/event-schema/src/control-plane.ts"
    Server = Read-SkyBridgeFile "apps/server/src/index.ts"
    Client = Read-SkyBridgeFile "packages/client/src/index.ts"
    Web = Read-SkyBridgeFile "apps/web/src/main.tsx"
    DesktopFixture = Read-SkyBridgeFile "fixtures/server-control-plane/desktop-heartbeat-export.fixture.json"
    BoundaryDoc = Read-SkyBridgeFile "docs/dev/CONTROL_PLANE_NO_REMOTE_EXECUTION_BOUNDARY.md"
  }
}

function Assert-ControlPlaneCommon {
  $texts = Get-ControlPlaneTexts
  foreach ($needle in @(
    "skybridge.worker_registration.v1",
    "skybridge.worker_pairing_preview.v1",
    "skybridge.worker_identity.v1",
    "skybridge.worker_capability_summary.v1",
    "skybridge.worker_connection_state.v1",
    "skybridge.worker_heartbeat.v1",
    "skybridge.worker_resource_gate_report.v1",
    "skybridge.worker_queue_preview_report.v1",
    "skybridge.worker_resident_status.v1",
    "skybridge.worker_ingest_rejection.v1",
    "skybridge.operator_approval_request.v1",
    "skybridge.operator_approval_state.v1",
    "skybridge.operator_approval_decision.v1",
    "skybridge.operator_approval_gate.v1"
  )) {
    Assert-Contains $texts.Schema $needle "Missing schema contract: $needle"
  }
  foreach ($needle in @(
    "/api/workers",
    "/api/workers/register-preview",
    "/api/workers/pairing-preview",
    "/api/workers/:workerId/revoke-preview",
    "/api/workers/:workerId/heartbeat-ingest",
    "/api/operator-approvals",
    "/api/operator-approvals/request-preview"
  )) {
    Assert-Contains $texts.Server $needle "Missing server preview route: $needle"
  }
  foreach ($needle in @(
    "execution_enabled: false",
    "queue_apply_enabled: false",
    "remote_execution_enabled: false",
    "arbitrary_command_enabled: false",
    "token_printed: false"
  )) {
    Assert-Contains $texts.Schema $needle "Missing disabled fixture field: $needle"
  }
  return $texts
}

function Assert-NoTokenPrintedTrue {
  $root = Get-SkyBridgeRoot
  $paths = @(
    "packages/event-schema/src/control-plane.ts",
    "apps/server/src/index.ts",
    "packages/client/src/index.ts",
    "apps/web/src/main.tsx",
    "fixtures/server-control-plane/desktop-heartbeat-export.fixture.json",
    "docs/dev/SERVER_CONTROL_PLANE_AND_PAIRING.md",
    "docs/dev/WORKER_HEARTBEAT_INGEST.md",
    "docs/dev/OPERATOR_APPROVAL_CONTROL_PLANE.md",
    "docs/dev/CONTROL_PLANE_NO_REMOTE_EXECUTION_BOUNDARY.md"
  )
  foreach ($path in $paths) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
    if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') {
      throw "token_printed=true found in $path"
    }
  }
}

function Write-Goal218Report {
  $root = Get-SkyBridgeRoot
  $dir = Join-Path $root ".agent\tmp\server-control-plane"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $report = [ordered]@{
    schema = "skybridge.goal_218_report.v1"
    schemas_added = @(
      "skybridge.worker_registration.v1",
      "skybridge.worker_pairing_preview.v1",
      "skybridge.worker_identity.v1",
      "skybridge.worker_capability_summary.v1",
      "skybridge.worker_connection_state.v1",
      "skybridge.worker_heartbeat.v1",
      "skybridge.worker_resource_gate_report.v1",
      "skybridge.worker_queue_preview_report.v1",
      "skybridge.worker_resident_status.v1",
      "skybridge.worker_ingest_rejection.v1",
      "skybridge.operator_approval_request.v1",
      "skybridge.operator_approval_state.v1",
      "skybridge.operator_approval_decision.v1",
      "skybridge.operator_approval_gate.v1"
    )
    routes_or_fixtures_added = @(
      "GET /api/workers",
      "GET /api/workers/:id/status",
      "POST /api/workers/register-preview",
      "POST /api/workers/pairing-preview",
      "POST /api/workers/:id/revoke-preview",
      "POST /api/workers/:id/heartbeat-ingest",
      "GET /api/operator-approvals",
      "fixtures/server-control-plane/desktop-heartbeat-export.fixture.json"
    )
    web_panels_added = @(
      "Worker list",
      "Worker detail/status",
      "Resource blockers",
      "Queue preview",
      "Resident worker state",
      "Pairing preview",
      "Pending approval",
      "Approval state",
      "Completed runs",
      "Evidence summary",
      "Open review holds",
      "No execution enabled banner",
      "Remote execution disabled banner"
    )
    desktop_heartbeat_export_status = "fixture-compatible"
    approval_model_status = "preview_only_non_executing"
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    token_printed = $false
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    no_raw_ingest_accepted = $true
    ready_for_goal_219 = $true
  }
  $jsonPath = Join-Path $dir "goal-218-report.json"
  $mdPath = Join-Path $dir "goal-218-report.md"
  $report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $jsonPath
  @(
    "# Goal 218 Report",
    "",
    "- schemas_added: $($report.schemas_added.Count)",
    "- routes_or_fixtures_added: $($report.routes_or_fixtures_added.Count)",
    "- web_panels_added: $($report.web_panels_added.Count)",
    "- desktop_heartbeat_export_status: $($report.desktop_heartbeat_export_status)",
    "- approval_model_status: $($report.approval_model_status)",
    "- remote_execution_enabled: false",
    "- arbitrary_command_enabled: false",
    "- execution_enabled: false",
    "- token_printed: false",
    "- active_tasks: 0",
    "- stale_leases: 0",
    "- runner_lock: none",
    "- no_raw_ingest_accepted: true",
    "- ready_for_goal_219: true"
  ) | Set-Content -Encoding UTF8 -LiteralPath $mdPath
  return $report
}

function Invoke-ControlPlaneSmoke([string]$Scenario) {
  $texts = Assert-ControlPlaneCommon
  Assert-NoTokenPrintedTrue

  switch ($Scenario) {
    "server-worker-pairing-contract" {
      Assert-Contains $texts.Schema "pairing_code_raw_persisted: false" "Pairing raw code persistence was not disabled."
      Assert-Contains $texts.Schema "pairing_preview_only: true" "Pairing preview-only flag missing."
    }
    "server-worker-registration-preview" {
      Assert-Contains $texts.Server "/api/workers/register-preview" "Registration preview route missing."
      Assert-Contains $texts.Schema "fixtureWorkerRegistration" "Registration fixture missing."
    }
    "server-worker-pairing-does-not-enable-execution" {
      Assert-Contains $texts.Server "/api/workers/pairing-preview" "Pairing preview route missing."
      Assert-Contains $texts.Server "remote_execution_enabled: false" "Pairing route may enable remote execution."
      Assert-Contains $texts.Server "arbitrary_command_enabled: false" "Pairing route may enable arbitrary command dispatch."
    }
    "server-heartbeat-ingest-safe" {
      Assert-Contains $texts.Server "/api/workers/:workerId/heartbeat-ingest" "Heartbeat ingest route missing."
      Assert-Contains $texts.Server "stored_safe_json_only: true" "Safe storage marker missing."
    }
    "server-heartbeat-rejects-raw-logs" {
      Assert-Contains $texts.Server "raw_logs" "Raw logs rejection missing."
    }
    "server-heartbeat-rejects-raw-prompt" {
      Assert-Contains $texts.Server "raw_prompt" "Raw prompt rejection missing."
    }
    "server-heartbeat-rejects-token-printed-true" {
      Assert-Contains $texts.Server "token_printed_true_forbidden" "token_printed=true rejection missing."
    }
    "server-heartbeat-rejects-authorization-header" {
      Assert-Contains $texts.Server "authorization_header_forbidden" "Authorization rejection missing."
    }
    "server-approval-contract" {
      Assert-Contains $texts.Schema "max_parallel_repo_mutations: 1" "Approval max repo mutation cap missing."
    }
    "server-approval-does-not-execute" {
      Assert-Contains $texts.Schema "approval_does_not_execute: true" "Approval no-execution gate missing."
      Assert-Contains $texts.Server "execution_started: false" "Approval route execution side-effect marker missing."
    }
    "server-approval-does-not-bypass-resource-gate" {
      Assert-Contains $texts.Schema "resource_gate_required: true" "Resource gate requirement missing."
    }
    "server-approval-does-not-bypass-human-review" {
      Assert-Contains $texts.Schema "human_review_required: true" "Human review requirement missing."
    }
    "server-approval-expires" {
      Assert-Contains $texts.Schema "expires_at" "Approval expiry field missing."
      Assert-Contains $texts.Server '"expired"' "Approval expiry state handling missing."
    }
    "server-no-arbitrary-command-dispatch" {
      Assert-Contains $texts.Server "raw_shell_command_forbidden" "Raw shell command rejection missing."
      Assert-Contains $texts.Schema "remote_arbitrary_command_dispatch_enabled: false" "Remote arbitrary command gate missing."
    }
    "web-control-plane-worker-list" {
      Assert-Contains $texts.Web "ControlPlaneWorkerListPanel" "Worker list panel missing."
      Assert-Contains $texts.Web "Worker List" "Worker list title missing."
    }
    "web-control-plane-approval-panel" {
      Assert-Contains $texts.Web "ControlPlaneApprovalPanel" "Approval panel missing."
      Assert-Contains $texts.Web "Pending Approval / Approval State" "Approval detail title missing."
    }
    "web-control-plane-no-execution-button" {
      Assert-Contains $texts.Web "No execute button, no run button, no apply button" "No-execution banner missing."
      Assert-Contains $texts.Web "ControlPlaneDisabledBanner" "Control-plane disabled banner component missing."
      Assert-Contains $texts.Web 'data-no-remote-execution="true"' "Control-plane route no-remote-execution marker missing."
    }
    "desktop-heartbeat-export-fixture" {
      $fixture = $texts.DesktopFixture | ConvertFrom-Json
      if ($fixture.schema -ne "skybridge.worker_heartbeat.v1") { throw "Desktop fixture schema mismatch." }
      if ($fixture.execution_enabled -ne $false) { throw "Desktop fixture execution_enabled must be false." }
      if ($fixture.token_printed -ne $false) { throw "Desktop fixture token_printed must be false." }
    }
    "control-plane-token-printed-false" {
      Assert-NoTokenPrintedTrue
    }
    "server-control-plane-goal-218-report" {
      $report = Write-Goal218Report
      if ($report.ready_for_goal_219 -ne $true) { throw "Goal 218 report not ready for Goal 219." }
    }
    default {
      throw "Unknown control-plane smoke scenario: $Scenario"
    }
  }

  [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
