$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-JsonScript([string]$ScriptName, [string]$Command) {
  $root = Get-SkyBridgeRoot
  $script = Join-Path $root "scripts\powershell\$ScriptName"
  return (& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Json | ConvertFrom-Json)
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

function Assert-RequiredDocs {
  $root = Get-SkyBridgeRoot
  foreach ($path in @(
    "docs/dev/DURABLE_WORKER_PAIRING_STORE.md",
    "docs/dev/PERSISTENT_OPERATOR_APPROVAL_STATE.md",
    "docs/dev/PAIRING_APPROVAL_SECURITY_MODEL.md",
    "docs/dev/CONTROL_PLANE_DURABLE_STATE_RUNBOOK.md",
    "docs/dev/RESIDENT_POLLING_PREVIEW.md",
    "docs/dev/DESKTOP_SERVER_SYNC_DISABLED_EXECUTION.md",
    "docs/dev/RESIDENT_POLLING_SAFETY_MODEL.md"
  )) {
    $full = Join-Path $root $path
    if (-not (Test-Path -LiteralPath $full)) { throw "Missing doc: $path" }
    Assert-NoTokenPrintedTrueInText (Get-Content -Raw -LiteralPath $full) $path
  }
}

function Invoke-Goal223224Smoke([string]$Scenario) {
  $root = Get-SkyBridgeRoot
  switch ($Scenario) {
    "worker-pairing-store-contract" {
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview"
      if ($result.pairing.schema -ne "skybridge.worker_pairing_record.v1") { throw "Pairing record schema mismatch." }
      Assert-False $result.pairing.raw_pairing_code_persisted "Raw pairing code persisted."
      Assert-False $result.pairing.execution_enabled "Pairing enabled execution."
    }
    "worker-pairing-create-consume-preview" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview" | Out-Null
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-consume-preview"
      if ($result.pairing.pairing_state -ne "paired") { throw "Pairing was not consumed." }
      Assert-False $result.execution_enabled "Consume enabled execution."
    }
    "worker-pairing-revoke-expire" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview" | Out-Null
      $revoked = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-revoke-preview"
      if ($revoked.pairing.pairing_state -ne "revoked") { throw "Pairing was not revoked." }
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview" | Out-Null
      $expired = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-expire-fixture"
      if ($expired.pairing.pairing_state -ne "expired") { throw "Pairing was not expired." }
    }
    "worker-pairing-no-raw-code-persistence" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview" | Out-Null
      $storePath = Join-Path $root ".agent\tmp\server-control-plane\pairing-store\pairing-store.json"
      $text = Get-Content -Raw -LiteralPath $storePath
      Assert-NoTokenPrintedTrueInText $text $storePath
      if ($text -match "preview-pairing-code-1234|`"raw_pairing_code`"\s*:|`"pairing_code`"\s*:|`"raw_token`"\s*:") { throw "Raw pairing code persisted." }
    }
    "worker-pairing-rejects-token-payload" {
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "security-rejection-fixtures"
      if ($result.rejected_case_count -lt 13) { throw "Expected all rejection fixtures." }
    }
    "worker-pairing-does-not-enable-execution" {
      $report = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-store-report"
      Assert-False $report.execution_enabled "Pairing report enabled execution."
      Assert-False $report.remote_execution_enabled "Pairing report enabled remote execution."
      Assert-False $report.arbitrary_command_enabled "Pairing report enabled arbitrary command."
    }
    "operator-approval-store-contract" {
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-create-preview"
      if ($result.approval.schema -ne "skybridge.operator_approval_record.v1") { throw "Approval record schema mismatch." }
      Assert-True $result.approval.resource_gate_required "Resource gate not required."
      Assert-False $result.approval.can_execute_now "Approval can execute now."
    }
    "operator-approval-consume-preview" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-create-preview" | Out-Null
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-approve-preview" | Out-Null
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-consume-preview"
      if ($result.approval.state -ne "consumed") { throw "Approval was not consumed." }
      Assert-False $result.execution_started "Approval consumption executed work."
    }
    "operator-approval-rejects-shell-command" {
      $result = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "security-rejection-fixtures"
      if ($result.rejected_case_count -lt 13) { throw "Shell command rejection fixture missing." }
    }
    "operator-approval-does-not-execute" {
      $report = Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-store-report"
      Assert-False $report.can_execute_now "Approval report can execute now."
      Assert-False $report.execution_enabled "Approval report enabled execution."
    }
    "pairing-approval-audit-events" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "pairing-create-preview" | Out-Null
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "approval-create-preview" | Out-Null
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "security-rejection-fixtures" | Out-Null
      foreach ($path in @(
        ".agent/tmp/server-control-plane/pairing-audit-report.json",
        ".agent/tmp/server-control-plane/approval-audit-report.json"
      )) {
        $full = Join-Path $root $path
        if (-not (Test-Path -LiteralPath $full)) { throw "Missing audit report: $path" }
        Assert-NoTokenPrintedTrueInText (Get-Content -Raw -LiteralPath $full) $path
      }
    }
    "resident-polling-policy" {
      $policy = Invoke-JsonScript "skybridge-resident-polling.ps1" "policy"
      Assert-False $policy.polling_enabled "Polling enabled by default."
      if ($policy.poll_interval_seconds -lt 300) { throw "Poll interval is too low." }
    }
    "resident-polling-preview-once" {
      $report = Invoke-JsonScript "skybridge-resident-polling.ps1" "preview-once"
      if (@($report.iterations).Count -lt 1) { throw "Preview once did not record an iteration." }
      Assert-False $report.codex_executed "Preview once executed Codex."
    }
    "resident-polling-preview-loop-fixture" {
      $report = Invoke-JsonScript "skybridge-resident-polling.ps1" "preview-loop-fixture"
      if (@($report.iterations).Count -lt 1) { throw "Preview loop did not record iterations." }
      Assert-False $report.task_claimed "Preview loop claimed a task."
    }
    "resident-polling-no-task-claim" {
      $gate = Invoke-JsonScript "skybridge-resident-polling.ps1" "no-execution-gate"
      Assert-False $gate.claim_enabled "Claim enabled."
      Assert-False $gate.codex_executed "Codex executed."
    }
    "resident-polling-no-codex-execution" {
      $gate = Invoke-JsonScript "skybridge-resident-polling.ps1" "no-execution-gate"
      Assert-False $gate.codex_executed "Codex executed."
      Assert-False $gate.execution_enabled "Execution enabled."
    }
    "resident-polling-no-queue-apply" {
      $gate = Invoke-JsonScript "skybridge-resident-polling.ps1" "no-execution-gate"
      Assert-False $gate.queue_apply_enabled "Queue apply enabled."
    }
    "desktop-pairing-polling-panel" {
      $text = Get-Content -Raw -LiteralPath (Join-Path $root "apps\desktop\src\main.tsx")
      foreach ($needle in @("Pairing status", "Approval state summary", "Resident polling preview status", "Claim disabled")) {
        if ($text -notmatch [regex]::Escape($needle)) { throw "Desktop panel missing: $needle" }
      }
      Assert-NoTokenPrintedTrueInText $text "apps/desktop/src/main.tsx"
    }
    "web-pairing-polling-panel" {
      $text = Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")
      foreach ($needle in @("Pairing store list", "Approval store list", "Worker polling status", "No arbitrary command banner")) {
        if ($text -notmatch [regex]::Escape($needle)) { throw "Web panel missing: $needle" }
      }
      Assert-NoTokenPrintedTrueInText $text "apps/web/src/main.tsx"
    }
    "resident-polling-token-printed-false" {
      Invoke-JsonScript "skybridge-resident-polling.ps1" "report" | Out-Null
      $text = Get-Content -Raw -LiteralPath (Join-Path $root ".agent\tmp\resident-polling\goal-224-report.json")
      Assert-NoTokenPrintedTrueInText $text "goal-224-report.json"
    }
    "goal-223-224-report" {
      Invoke-JsonScript "skybridge-control-plane-durable-state.ps1" "goal-223-report" | Out-Null
      Invoke-JsonScript "skybridge-resident-polling.ps1" "report" | Out-Null
      Assert-RequiredDocs
      foreach ($path in @(
        ".agent/tmp/server-control-plane/goal-223-report.json",
        ".agent/tmp/server-control-plane/goal-223-report.md",
        ".agent/tmp/resident-polling/goal-224-report.json",
        ".agent/tmp/resident-polling/goal-224-report.md"
      )) {
        $full = Join-Path $root $path
        if (-not (Test-Path -LiteralPath $full)) { throw "Missing report: $path" }
        Assert-NoTokenPrintedTrueInText (Get-Content -Raw -LiteralPath $full) $path
      }
    }
    default { throw "Unknown Goal 223/224 smoke scenario: $Scenario" }
  }

  [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
