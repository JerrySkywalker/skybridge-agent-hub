$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Read-SkyBridgeFile([string]$RelativePath) {
  return Get-Content -Raw -LiteralPath (Join-Path (Get-SkyBridgeRoot) $RelativePath)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text -notmatch [regex]::Escape($Needle)) { throw $Message }
}

function Invoke-ReleaseJson([string[]]$Arguments) {
  $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-release.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-boinc-v1-release failed." }
  return $raw | ConvertFrom-Json
}

function Assert-NoTokenPrintedTrue {
  $root = Get-SkyBridgeRoot
  $paths = @(
    "packages/event-schema/src/reliability.ts",
    "packages/client/src/index.ts",
    "apps/web/src/main.tsx",
    "apps/desktop/src/main.tsx",
    "scripts/powershell/skybridge-boinc-v1-release.ps1",
    "docs/dev/BOINC_LIKE_V1_CONTROLLED_RELEASE.md",
    "docs/dev/OPERATOR_RUNBOOK_V1.md",
    "docs/dev/DESKTOP_WORKER_V1_RUNBOOK.md",
    "docs/dev/SERVER_CONTROL_PLANE_RUNBOOK.md",
    "docs/dev/SECURITY_AND_AUDIT_MODEL_V1.md",
    "docs/dev/FAILURE_RECOVERY_RUNBOOK_V1.md",
    "docs/dev/RELEASE_NOTES_V1.md",
    "docs/dev/CONTROLLED_RELEASE_INSTALL_AND_LAUNCH.md",
    "docs/dev/V1_POST_RELEASE_CHECKLIST.md",
    "docs/dev/V1_NEXT_STAGE_CONTROLLED_TRIAL_PLAN.md",
    "docs/dev/V1_CONTROLLED_TRIAL_BACKLOG.md",
    "docs/dev/V1_TO_V1_1_ROADMAP.md",
    "README.md"
  )
  foreach ($path in $paths) {
    $full = Join-Path $root $path
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') {
      throw "token_printed=true found in $path"
    }
  }
}

function Assert-ReleaseContracts {
  $schema = Read-SkyBridgeFile "packages/event-schema/src/reliability.ts"
  foreach ($needle in @(
    "skybridge.boinc_v1_release_status.v1",
    "skybridge.boinc_v1_release_readiness.v1",
    "skybridge.boinc_v1_release_gate.v1",
    "skybridge.boinc_v1_controlled_release_policy.v1",
    "skybridge.boinc_v1_release_report.v1",
    "skybridge.boinc_v1_release_blocker.v1",
    "skybridge.boinc_v1_release_tag_plan.v1",
    "skybridge.boinc_v1_release_approval.v1",
    "skybridge.boinc_v1_operator_release_decision.v1",
    "skybridge.boinc_v1_controlled_apply_boundary.v1",
    "skybridge.boinc_v1_release_operator_policy.v1"
  )) {
    Assert-Contains $schema $needle "Missing release contract: $needle"
  }
}

function Invoke-BoincV1ReleaseSmoke([string]$Scenario) {
  Assert-ReleaseContracts
  Assert-NoTokenPrintedTrue
  $root = Get-SkyBridgeRoot
  $web = Read-SkyBridgeFile "apps/web/src/main.tsx"
  $desktop = Read-SkyBridgeFile "apps/desktop/src/main.tsx"
  switch ($Scenario) {
    "readiness-gate" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.gate_result -ne "pass" -or $gate.can_execute_now -ne $false) { throw "Release gate unsafe." }
      if ($gate.readiness.active_tasks -ne 0 -or $gate.readiness.runner_lock -ne "none") { throw "Release readiness active state unsafe." }
    }
    "approval-contract" {
      $approval = Invoke-ReleaseJson @("-Command", "release-approval-preview")
      if ($approval.schema -ne "skybridge.boinc_v1_release_approval.v1") { throw "Release approval schema mismatch." }
      if ($approval.can_execute_now -ne $false -or $approval.max_parallel_repo_mutations -ne 1) { throw "Release approval can execute or mutate unsafely." }
    }
    "no-default-execution" {
      $gate = Invoke-ReleaseJson @("-Command", "no-execution-gate")
      if ($gate.can_execute_now -ne $false -or $gate.workunit_creation_enabled -ne $false -or $gate.task_claim_enabled -ne $false) { throw "No-execution gate unsafe." }
    }
    "requires-resource-gate" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.policy.require_resource_gate -ne $true -or $gate.readiness.resource_gate_ready -ne $true) { throw "Resource gate not required." }
    }
    "requires-audit" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.policy.require_audit -ne $true -or $gate.readiness.audit_redaction_ready -ne $true) { throw "Audit not required." }
    }
    "requires-evidence-retention" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.policy.require_evidence_retention -ne $true -or $gate.readiness.evidence_retention_hash_chain_ready -ne $true) { throw "Evidence retention not required." }
    }
    "requires-failure-budget" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.policy.require_failure_budget -ne $true -or $gate.readiness.failure_budget_ready -ne $true) { throw "Failure budget not required." }
    }
    "desktop-status" {
      Assert-Contains $desktop "BoincV1ReleaseStatusPanel" "Desktop release status panel missing."
      Assert-Contains $desktop "BOINC-like v1 Release" "Desktop release title missing."
    }
    "server-status" {
      $gate = Invoke-ReleaseJson @("-Command", "gate")
      if ($gate.readiness.server_control_plane_ready -ne $true -or $gate.readiness.remote_execution_enabled -ne $false) { throw "Server release status unsafe." }
    }
    "docs-present" {
      foreach ($path in @(
        "docs/dev/BOINC_LIKE_V1_CONTROLLED_RELEASE.md",
        "docs/dev/OPERATOR_RUNBOOK_V1.md",
        "docs/dev/DESKTOP_WORKER_V1_RUNBOOK.md",
        "docs/dev/SERVER_CONTROL_PLANE_RUNBOOK.md",
        "docs/dev/SECURITY_AND_AUDIT_MODEL_V1.md",
        "docs/dev/FAILURE_RECOVERY_RUNBOOK_V1.md",
        "docs/dev/RELEASE_NOTES_V1.md",
        "docs/dev/CONTROLLED_RELEASE_INSTALL_AND_LAUNCH.md",
        "docs/dev/V1_POST_RELEASE_CHECKLIST.md",
        "docs/dev/V1_NEXT_STAGE_CONTROLLED_TRIAL_PLAN.md",
        "docs/dev/V1_CONTROLLED_TRIAL_BACKLOG.md",
        "docs/dev/V1_TO_V1_1_ROADMAP.md"
      )) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { throw "Missing doc $path" }
      }
      Assert-Contains (Read-SkyBridgeFile "README.md") "BOINC-like v1 controlled release" "README release section missing."
    }
    "tag-preview" {
      $tag = Invoke-ReleaseJson @("-Command", "tag-preview")
      if ($tag.force_tag -ne $false -or $tag.tag -ne "v0.99.0-boinc-like-v1-controlled-release") { throw "Tag preview unsafe." }
      if ($tag.tag_exists -eq $true -and $tag.tag_matches_target -ne $true) { throw "Existing tag points elsewhere." }
    }
    "postrelease-report" {
      $report = Invoke-ReleaseJson @("-Command", "release-report")
      if ($report.release_gate_result -ne "pass" -or $report.ready_for_goal_221 -ne $true) { throw "Postrelease report unsafe." }
      foreach ($path in @(
        ".agent/tmp/release/boinc-like-v1-controlled-release-report.json",
        ".agent/tmp/release/boinc-like-v1-controlled-release-report.md",
        ".agent/tmp/release/postrelease-smoke-report.json",
        ".agent/tmp/release/postrelease-smoke-report.md"
      )) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { throw "Missing release report $path" }
      }
    }
    "no-enabled-execution-buttons" {
      foreach ($needle in @("BoincV1ReleaseDashboard", "No execution enabled banner", "No enabled execute/run/apply/start controls")) {
        Assert-Contains $web $needle "Web release dashboard missing $needle"
      }
      if ($web -match 'onClick=\{[^}]*execute|onClick=\{[^}]*apply|<input[^>]*command') { throw "Web may expose execution command UI." }
    }
    "token-printed-false" {
      Assert-NoTokenPrintedTrue
      $status = Invoke-ReleaseJson @("-Command", "status")
      if ($status.token_printed -ne $false) { throw "Release status token_printed must be false." }
    }
    default { throw "Unknown release smoke scenario: $Scenario" }
  }
  [pscustomobject]@{
    ok = $true
    scenario = "boinc-v1-release-$Scenario"
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
