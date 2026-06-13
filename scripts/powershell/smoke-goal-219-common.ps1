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

function Assert-NotUnsafeTokenPrinted {
  $root = Get-SkyBridgeRoot
  $paths = @(
    "packages/event-schema/src/reliability.ts",
    "packages/client/src/index.ts",
    "apps/web/src/main.tsx",
    "apps/desktop/src/main.tsx",
    "scripts/powershell/skybridge-failure-budget.ps1",
    "scripts/powershell/skybridge-evidence-retention.ps1",
    "scripts/powershell/skybridge-audit-trail.ps1",
    "docs/dev/FAILURE_BUDGET_POLICY.md",
    "docs/dev/EVIDENCE_RETENTION_AND_HASH_CHAIN.md",
    "docs/dev/AUDIT_TRAIL_AND_REDACTION.md",
    "docs/dev/BOINC_V1_RELEASE_AUDIT_CHECKLIST.md",
    "docs/dev/SAFE_EXPORT_GATE.md"
  )
  foreach ($path in $paths) {
    $full = Join-Path $root $path
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') {
      throw "Unsafe token_printed truthy value found in $path"
    }
  }
}

function Invoke-Goal219Json([string]$ScriptName, [string[]]$Arguments) {
  $script = Join-Path $PSScriptRoot $ScriptName
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$ScriptName failed." }
  return $raw | ConvertFrom-Json
}

function Assert-Goal219Contracts {
  $schema = Read-SkyBridgeFile "packages/event-schema/src/reliability.ts"
  foreach ($needle in @(
    "skybridge.failure_budget.v1",
    "skybridge.failure_classification.v1",
    "skybridge.retry_authorization_gate.v1",
    "skybridge.replacement_authorization_gate.v1",
    "skybridge.failure_budget_report.v1",
    "skybridge.failure_budget_blocker.v1",
    "skybridge.evidence_retention.v1",
    "skybridge.evidence_index_entry.v1",
    "skybridge.evidence_hash_chain.v1",
    "skybridge.evidence_export_summary.v1",
    "skybridge.evidence_retention_report.v1",
    "skybridge.evidence_retention_violation.v1",
    "skybridge.audit_event.v1",
    "skybridge.audit_trail.v1",
    "skybridge.audit_report.v1",
    "skybridge.redaction_scan_result.v1",
    "skybridge.redaction_violation.v1",
    "skybridge.safe_export_gate.v1"
  )) {
    Assert-Contains $schema $needle "Missing Goal 219 contract: $needle"
  }
  Assert-Contains $schema "no_silent_rerun: true" "Failure budget no-silent-rerun fixture missing."
  Assert-Contains $schema "automatic_retry_allowed: false" "Retry gate must refuse automatic retry."
  Assert-Contains $schema "automatic_replacement_allowed: false" "Replacement gate must refuse automatic replacement."
}

function Invoke-Goal219Smoke([string]$Scenario) {
  Assert-Goal219Contracts
  Assert-NotUnsafeTokenPrinted
  $root = Get-SkyBridgeRoot
  $web = Read-SkyBridgeFile "apps/web/src/main.tsx"
  $desktop = Read-SkyBridgeFile "apps/desktop/src/main.tsx"

  switch ($Scenario) {
    "failure-budget-contract" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "status")
      if ($result.schema -ne "skybridge.failure_budget_report.v1") { throw "Failure budget report schema mismatch." }
      if ($result.policy.no_silent_rerun -ne $true) { throw "no_silent_rerun must be true." }
    }
    "failure-budget-no-silent-rerun" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "retry-gate")
      if ($result.automatic_retry_allowed -ne $false -or $result.no_silent_rerun -ne $true) { throw "Silent rerun was not refused." }
    }
    "failure-budget-retry-requires-authorization" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "retry-gate")
      if ($result.explicit_operator_authorization_required -ne $true) { throw "Retry authorization requirement missing." }
    }
    "failure-budget-replacement-requires-no-mutation" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "replacement-gate", "-Scenario", "nonzero_no_mutation")
      if ($result.requires_no_mutation_classification -ne $true -or $result.automatic_replacement_allowed -ne $false) { throw "Replacement gate unsafe." }
    }
    "failure-budget-blocks-pr-created-retry" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "retry-gate", "-Scenario", "pr_created_hold")
      if ($result.blocked -ne $true -or $result.automatic_retry_allowed -ne $false) { throw "PR-created retry was not blocked." }
    }
    "failure-budget-blocks-raw-artifacts" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "retry-gate", "-Scenario", "raw_artifact_detected")
      if ($result.blocked -ne $true) { throw "Raw artifact retry was not blocked." }
    }
    "failure-budget-blocks-token-printed-true" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "retry-gate", "-Scenario", "token_printed_true")
      if ($result.blocked -ne $true) { throw "Token printed scenario was not blocked." }
    }
    "failure-budget-token-printed-false" {
      $result = Invoke-Goal219Json "skybridge-failure-budget.ps1" @("-Command", "status")
      if ($result.token_printed -ne $false) { throw "Failure budget token_printed must be false." }
    }
    "evidence-retention-index" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "index")
      if (@($result.entries).Count -lt 1) { throw "Evidence index is empty." }
      if (($result.entries | Where-Object { $_.raw_artifact -ne $false }).Count -gt 0) { throw "Raw artifact entered evidence index." }
    }
    "evidence-retention-hash-chain" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "verify-chain")
      if ($result.schema -ne "skybridge.evidence_hash_chain.v1" -or $result.verified -ne $true) { throw "Hash chain verification failed." }
    }
    "evidence-retention-detects-missing-evidence" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "fixture-missing-evidence")
      if (($result.violations | Where-Object { $_.violation_type -eq "missing_expected_evidence" }).Count -lt 1) { throw "Missing evidence fixture not detected." }
    }
    "evidence-retention-detects-mismatch" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "fixture-hash-mismatch")
      if (($result.violations | Where-Object { $_.violation_type -eq "hash_mismatch" }).Count -lt 1) { throw "Hash mismatch fixture not detected." }
    }
    "evidence-retention-safe-export" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "export-safe-summary")
      if ($result.raw_artifact_count -ne 0 -or $result.secret_detected_count -ne 0) { throw "Safe export summary is unsafe." }
    }
    "evidence-retention-rejects-raw-artifact" {
      $script = Read-SkyBridgeFile "scripts/powershell/skybridge-evidence-retention.ps1"
      Assert-Contains $script "Test-RawArtifactName" "Raw artifact rejection helper missing."
      Assert-Contains $script "*.stdout*" "stdout exclusion missing."
    }
    "evidence-retention-token-printed-false" {
      $result = Invoke-Goal219Json "skybridge-evidence-retention.ps1" @("-Command", "scan")
      if ($result.token_printed -ne $false) { throw "Evidence retention token_printed must be false." }
    }
    "audit-event-contract" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "event-fixture")
      if ($result.schema -ne "skybridge.audit_event.v1") { throw "Audit event schema mismatch." }
    }
    "audit-finalizer-event" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "build-trail")
      if (($result.events | Where-Object { $_.event_type -eq "finalizer_completed" }).Count -lt 1) { throw "Finalizer audit event missing." }
    }
    "audit-approval-event-preview" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "build-trail")
      if (($result.events | Where-Object { $_.event_type -eq "approval_approved_preview" }).Count -lt 1) { throw "Approval preview audit event missing." }
    }
    "audit-heartbeat-ingest-event" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "build-trail")
      if (($result.events | Where-Object { $_.event_type -eq "server_heartbeat_ingested" }).Count -lt 1) { throw "Heartbeat audit event missing." }
    }
    "redaction-rejects-token" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "redaction-scan", "-Scenario", "token")
      if ($result.passed -ne $false -or @($result.violations).Count -lt 1) { throw "Token fixture was not rejected." }
    }
    "redaction-rejects-raw-log-fields" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "redaction-scan", "-Scenario", "raw-log-fields")
      if ($result.passed -ne $false -or @($result.violations).Count -lt 1) { throw "Raw log field fixture was not rejected." }
    }
    "redaction-allows-safe-hashes" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "redaction-scan", "-Scenario", "safe-hashes")
      if ($result.passed -ne $true) { throw "Safe hashes fixture was not allowed." }
    }
    "safe-export-gate" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "safe-export-gate")
      if ($result.safe_to_export -ne $true -or $result.raw_prompt_persisted -ne $false -or $result.authorization_persisted -ne $false) { throw "Safe export gate unsafe." }
    }
    "desktop-audit-panel" {
      Assert-Contains $desktop "DesktopAuditPanel" "Desktop audit panel missing."
      Assert-Contains $desktop "Failure Budget / Audit" "Desktop audit panel title missing."
    }
    "web-audit-panel" {
      Assert-Contains $web "ReliabilityAuditPage" "Web audit page missing."
      Assert-Contains $web "Audit Trail Summary" "Web audit trail panel missing."
    }
    "audit-token-printed-false" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "report")
      if ($result.token_printed -ne $false) { throw "Audit report token_printed must be false." }
    }
    "goal-219-report" {
      $result = Invoke-Goal219Json "skybridge-audit-trail.ps1" @("-Command", "report")
      $reportPath = Join-Path $root ".agent\tmp\audit\goal-219-report.json"
      $goal = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
      if ($goal.ready_for_goal_220 -ne $true) { throw "Goal 219 report not ready for Goal 220." }
      if ($goal.token_printed -ne $false) { throw "Goal 219 report token_printed must be false." }
    }
    default { throw "Unknown Goal 219 smoke scenario: $Scenario" }
  }

  [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    queue_apply_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
