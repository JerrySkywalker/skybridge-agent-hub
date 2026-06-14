$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-Goal225Json([string]$Command, [string[]]$Extra = @()) {
  $root = Get-SkyBridgeRoot
  $script = Join-Path $root "scripts\powershell\skybridge-server-approved-workunit.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Json @Extra
  if ($LASTEXITCODE -ne 0) { throw "Goal 225 command failed: $Command" }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Assert-False($Value, [string]$Message) {
  if ($Value -ne $false) { throw $Message }
}

function Assert-True($Value, [string]$Message) {
  if ($Value -ne $true) { throw $Message }
}

function Assert-NoTokenPrintedTrueInText([string]$Text, [string]$Label) {
  if ($Text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') {
    throw "token_printed=true found in $Label"
  }
}

function Invoke-Goal225Smoke([string]$Scenario) {
  $root = Get-SkyBridgeRoot
  switch ($Scenario) {
    "server-approved-workunit-policy-contract" {
      $policy = Invoke-Goal225Json "policy"
      if ($policy.schema -ne "skybridge.server_approved_workunit_policy.v1") { throw "Policy schema mismatch." }
      if ($policy.mode -ne "server_approved_one_workunit") { throw "Policy mode mismatch." }
      Assert-False $policy.remote_execution_enabled "Remote execution enabled."
      Assert-False $policy.arbitrary_command_enabled "Arbitrary command enabled."
      Assert-False $policy.generic_queue_apply_enabled "Generic queue apply enabled."
    }
    "server-approved-workunit-gate" {
      $gate = Invoke-Goal225Json "gate"
      if ($gate.schema -ne "skybridge.server_approved_workunit_gate.v1") { throw "Gate schema mismatch." }
      if ($gate.release_gate_result -ne "pass") { throw "Release gate did not pass." }
      if ($gate.pairing_gate_result -ne "pass") { throw "Pairing gate did not pass." }
      if ($gate.approval_gate_result -ne "pass") { throw "Approval gate did not pass." }
      if ($gate.resident_polling_gate_result -ne "pass") { throw "Resident polling gate did not pass." }
    }
    "server-approved-workunit-preview" {
      $preview = Invoke-Goal225Json "preview"
      Assert-True $preview.no_mutation "Preview should be no-mutation."
      if ($preview.workunit.target_path -ne "docs/server-approved-workunit-225.md") { throw "Unexpected target path." }
    }
    "server-approved-workunit-no-default-execution" {
      $gate = Invoke-Goal225Json "apply-gate"
      if ($gate.gate_result -ne "blocked") { throw "Apply gate should block without explicit authorization." }
      if (-not (@($gate.blockers | ForEach-Object blocker_id) -contains "local_goal_authorization_required")) { throw "Missing local authorization blocker." }
    }
    "server-approved-workunit-requires-pairing" {
      $gate = Invoke-Goal225Json "gate" @("-SimulatePairingMissing")
      if ($gate.pairing_gate_result -ne "blocked") { throw "Expected pairing gate block." }
    }
    "server-approved-workunit-requires-approval" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateApprovalExpired")
      if ($gate.approval_gate_result -ne "blocked") { throw "Expected approval gate block." }
    }
    "server-approved-workunit-consumes-approval" {
      $result = Invoke-Goal225Json "apply" @("-AuthorizeServerApprovedRun225", "-AuthorizationReason", "smoke approval consumption", "-SimulateApply")
      if ($result.final_state -ne "held_waiting_human_review_server_approved_run_225") { throw "Expected human review hold." }
      $report = Invoke-Goal225Json "report"
      if ($report.gate.approval_consumption_status -ne "consumed") { throw "Approval was not consumed." }
    }
    "server-approved-workunit-requires-resident-polling" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateResidentPollingBlocked")
      if ($gate.resident_polling_gate_result -ne "block") { throw "Expected resident polling block." }
    }
    "server-approved-workunit-requires-resource-gate" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateResourceGateFail")
      if ($gate.resource_gate_result -ne "blocked") { throw "Expected resource gate block." }
    }
    "server-approved-workunit-requires-failure-budget" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateFailureBudgetBlocked")
      if ($gate.failure_budget_gate_result -ne "blocked") { throw "Expected failure budget block." }
    }
    "server-approved-workunit-requires-evidence-retention" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateEvidenceRetentionBlocked")
      if ($gate.evidence_retention_gate_result -ne "blocked") { throw "Expected evidence retention block." }
    }
    "server-approved-workunit-requires-audit" {
      $gate = Invoke-Goal225Json "gate" @("-SimulateAuditBlocked")
      if ($gate.audit_redaction_gate_result -ne "blocked" -or $gate.safe_export_gate_result -ne "blocked") { throw "Expected audit/safe export block." }
    }
    "server-approved-workunit-no-remote-execution" {
      $gate = Invoke-Goal225Json "no-execution-gate"
      Assert-False $gate.remote_execution_enabled "Remote execution enabled."
    }
    "server-approved-workunit-no-arbitrary-command" {
      $gate = Invoke-Goal225Json "no-execution-gate"
      Assert-False $gate.arbitrary_command_enabled "Arbitrary command enabled."
    }
    "server-approved-workunit-no-generic-queue-apply" {
      $gate = Invoke-Goal225Json "no-execution-gate"
      Assert-False $gate.generic_queue_apply_enabled "Generic queue apply enabled."
    }
    "server-approved-workunit-one-workunit-only" {
      $policy = Invoke-Goal225Json "policy"
      if ($policy.max_workunits -ne 1 -or $policy.max_tasks -ne 1 -or $policy.max_claims -ne 1 -or $policy.max_codex_executions -ne 1 -or $policy.max_task_prs -ne 1) {
        throw "One-workunit limits not enforced."
      }
    }
    "server-approved-workunit-finalizer-requires-merged-pr" {
      Invoke-Goal225Json "apply" @("-AuthorizeServerApprovedRun225", "-AuthorizationReason", "smoke finalizer gate", "-SimulateApply") | Out-Null
      $preview = Invoke-Goal225Json "finalizer-preview"
      if ($preview.final_state -ne "held_waiting_human_review_server_approved_run_225") { throw "Expected human review hold." }
      $apply = Invoke-Goal225Json "finalizer-apply"
      if ($apply.ok -ne $false) { throw "Finalizer apply should refuse unmerged PR." }
    }
    "server-approved-workunit-audit-events" {
      Invoke-Goal225Json "audit-preview" | Out-Null
      $path = Join-Path $root ".agent\tmp\server-approved-run-225\workunit-audit-report.json"
      if (-not (Test-Path -LiteralPath $path)) { throw "Missing audit report." }
      Assert-NoTokenPrintedTrueInText (Get-Content -Raw -LiteralPath $path) $path
    }
    "server-approved-workunit-safe-export" {
      Invoke-Goal225Json "audit-preview" | Out-Null
      $path = Join-Path $root ".agent\tmp\server-approved-run-225\workunit-safe-export-report.json"
      $report = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
      Assert-True $report.metadata_only "Safe export should be metadata-only."
      Assert-False $report.prompt_persisted "Prompt persisted."
    }
    "desktop-server-approved-workunit-panel" {
      $text = Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx")
      foreach ($needle in @("Server-approved Run 225", "Human review hold", "remote_execution_enabled=false", "queue_apply_enabled=false")) {
        if ($text -notmatch [regex]::Escape($needle)) { throw "Desktop panel missing: $needle" }
      }
    }
    "web-server-approved-workunit-panel" {
      $text = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
      foreach ($needle in @("Server-approved run 225", "task PR URL", "Human review hold", "No enabled execution buttons")) {
        if ($text -notmatch [regex]::Escape($needle)) { throw "Web panel missing: $needle" }
      }
    }
    "server-approved-workunit-token-printed-false" {
      foreach ($command in @("policy", "gate", "preview", "safe-summary", "audit-preview", "report", "no-execution-gate")) {
        $raw = Invoke-Goal225Json $command | ConvertTo-Json -Depth 20
        Assert-NoTokenPrintedTrueInText $raw $command
      }
    }
    default { throw "Unknown Goal 225 smoke scenario: $Scenario" }
  }

  [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    token_printed = $false
  } | ConvertTo-Json -Compress
}
