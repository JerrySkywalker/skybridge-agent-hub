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

function Invoke-TrialJson([string[]]$Arguments) {
  $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-controlled-trial.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-boinc-v1-controlled-trial failed." }
  return ($raw | Out-String).Trim() | ConvertFrom-Json
}

function Assert-NoTrialTokenPrintedTrue {
  $root = Get-SkyBridgeRoot
  $paths = @(
    "packages/event-schema/src/reliability.ts",
    "packages/client/src/index.ts",
    "apps/web/src/main.tsx",
    "apps/desktop/src/main.tsx",
    "scripts/powershell/skybridge-boinc-v1-controlled-trial.ps1",
    "docs/dev/BOINC_V1_CONTROLLED_TRIAL_221.md",
    "docs/dev/CONTROLLED_TRIAL_HUMAN_REVIEW_AND_FINALIZER.md",
    "docs/dev/CONTROLLED_TRIAL_AUDIT_EVIDENCE.md",
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

function Assert-TrialContracts {
  $schema = Read-SkyBridgeFile "packages/event-schema/src/reliability.ts"
  foreach ($needle in @(
    "skybridge.boinc_v1_controlled_trial.v1",
    "skybridge.boinc_v1_controlled_trial_approval.v1",
    "skybridge.boinc_v1_controlled_trial_gate.v1",
    "skybridge.boinc_v1_controlled_trial_policy.v1",
    "skybridge.boinc_v1_controlled_trial_blocker.v1"
  )) {
    Assert-Contains $schema $needle "Missing trial contract: $needle"
  }
}

function Invoke-BoincV1ControlledTrialSmoke([string]$Scenario) {
  Assert-TrialContracts
  Assert-NoTrialTokenPrintedTrue
  $root = Get-SkyBridgeRoot
  switch ($Scenario) {
    "approval-contract" {
      $approval = Invoke-TrialJson @("-Command", "approval-preview")
      if ($approval.schema -ne "skybridge.boinc_v1_controlled_trial_approval.v1") { throw "Approval schema mismatch." }
      if ($approval.max_workunits -ne 1 -or $approval.max_task_prs -ne 1 -or $approval.approval_can_execute_work -ne $false) { throw "Approval contract unsafe." }
    }
    "gate" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.gate_result -ne "pass" -or $gate.can_execute_one_workunit -ne $true) { throw "Trial gate did not pass." }
      if ($gate.max_workunits -ne 1 -or $gate.open_task_pr_count -ne 0) { throw "Trial gate limits unsafe." }
    }
    "preview" {
      $preview = Invoke-TrialJson @("-Command", "trial-preview")
      if ($preview.workunit_id -ne "boinc-v1-controlled-trial-221-workunit-001" -or $preview.target_path -ne "docs/boinc-v1-controlled-trial-221.md") { throw "Trial preview mismatch." }
    }
    "no-default-execution" {
      $gate = Invoke-TrialJson @("-Command", "no-execution-gate")
      if ($gate.approval_can_execute_work -ne $false -or $gate.generic_queue_apply_enabled -ne $false -or $gate.remote_execution_enabled -ne $false) { throw "No-execution gate unsafe." }
    }
    "requires-release-gate" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.release_gate.release_gate_result -ne "pass" -or $gate.release_gate.tag_exists -ne $true) { throw "Release gate not required." }
    }
    "requires-resource-gate" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221", "-SimulateResourceGateFail")
      if ($gate.gate_result -ne "blocked" -or @($gate.blockers) -notcontains "resource_gate_blocked") { throw "Resource gate failure did not block." }
    }
    "requires-failure-budget" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.reliability_gates.failure_budget_gate_result -ne "pass") { throw "Failure budget gate missing." }
    }
    "requires-evidence-retention" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.reliability_gates.evidence_retention_gate_result -ne "pass" -or $gate.reliability_gates.hash_chain_ready -ne $true) { throw "Evidence retention gate missing." }
    }
    "requires-audit" {
      $audit = Invoke-TrialJson @("-Command", "trial-audit-preview")
      if (@($audit.events | Where-Object { $_.event_type -eq "redaction_gate_passed" }).Count -ne 1) { throw "Audit event missing." }
    }
    "no-remote-execution" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.release_gate.remote_execution_enabled -ne $false -or $gate.approval_gate.allow_remote_execution -ne $false) { throw "Remote execution enabled." }
    }
    "no-generic-queue-apply" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.release_gate.generic_bounded_queue_apply_enabled -ne $false -or $gate.approval_gate.allow_generic_queue_apply -ne $false) { throw "Generic queue apply enabled." }
    }
    "one-workunit-only" {
      $gate = Invoke-TrialJson @("-Command", "trial-apply-gate", "-AuthorizeGoal221")
      if ($gate.max_workunits -ne 1 -or $gate.max_tasks -ne 1 -or $gate.max_claims -ne 1 -or $gate.max_task_prs -ne 1) { throw "Trial limit mismatch." }
    }
    "finalizer-requires-merged-pr" {
      $preview = Invoke-TrialJson @("-Command", "trial-finalizer-preview")
      if ($preview.can_apply -eq $true -or @($preview.blockers) -notcontains "task_pr_not_merged") { throw "Finalizer did not require merged task PR." }
    }
    "audit-events" {
      $audit = Invoke-TrialJson @("-Command", "trial-audit-preview")
      foreach ($event in @("release_gate_passed", "approval_gate_passed", "resource_gate_passed", "human_review_required", "no_next_execution_authorized")) {
        if (@($audit.events | Where-Object { $_.event_type -eq $event }).Count -ne 1) { throw "Missing audit event $event" }
      }
    }
    "safe-export" {
      Invoke-TrialJson @("-Command", "trial-audit-preview") | Out-Null
      $safe = Get-Content -Raw -LiteralPath (Join-Path $root ".agent/tmp/boinc-v1-controlled-trial-221/trial-safe-export-report.json") | ConvertFrom-Json
      if ($safe.safe_to_export -ne $true -or $safe.export_scope -ne "metadata_only") { throw "Safe export report unsafe." }
    }
    "desktop-panel" {
      $desktop = Read-SkyBridgeFile "apps/desktop/src/main.tsx"
      Assert-Contains $desktop "BoincV1ControlledTrialPanel" "Desktop controlled trial panel missing."
      Assert-Contains $desktop "held_waiting_human_review_controlled_trial_221" "Desktop human review hold missing."
    }
    "web-panel" {
      $web = Read-SkyBridgeFile "apps/web/src/main.tsx"
      Assert-Contains $web "BoincV1ControlledTrialPanel" "Web controlled trial panel missing."
      Assert-Contains $web "No enabled execution buttons" "Web no execution controls marker missing."
    }
    "token-printed-false" {
      Assert-NoTrialTokenPrintedTrue
      $status = Invoke-TrialJson @("-Command", "status")
      if ($status.token_printed -ne $false) { throw "Status token_printed must be false." }
    }
    default { throw "Unknown controlled trial smoke scenario: $Scenario" }
  }
  [pscustomobject]@{
    ok = $true
    scenario = "boinc-v1-controlled-trial-$Scenario"
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
