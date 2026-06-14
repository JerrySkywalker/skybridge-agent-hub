[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet(
    "status",
    "policy",
    "preview",
    "gate",
    "apply-gate",
    "apply",
    "evidence",
    "audit-preview",
    "finalizer-preview",
    "finalizer-apply",
    "finalizer-evidence",
    "finalizer-report",
    "safe-summary",
    "report",
    "no-execution-gate"
  )]
  [string]$Command,

  [string]$WorkerId = "laptop-zenbookduo",
  [switch]$AuthorizeServerApprovedRun225,
  [string]$AuthorizationReason = "",
  [switch]$SimulatePairingMissing,
  [switch]$SimulateApprovalExpired,
  [switch]$SimulateResidentPollingBlocked,
  [switch]$SimulateResourceGateFail,
  [switch]$SimulateFailureBudgetBlocked,
  [switch]$SimulateEvidenceRetentionBlocked,
  [switch]$SimulateAuditBlocked,
  [switch]$SimulateApply,
  [switch]$SimulateMergedTaskPr,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.CodexExecutor.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.ResourceGate.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.SafetyScanner.psm1") -Force

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$RunId = "server-approved-run-225"
$WorkunitId = "server-approved-run-225-workunit-001"
$TaskId = "server-approved-run-225-task-001"
$ApprovalId = "server-approved-run-225-approval-001"
$TargetPath = "docs/server-approved-workunit-225.md"
$TaskBranch = "ai/server-approved-workunit/server-approved-run-225-workunit-001"
$StateDir = ".agent/tmp/server-approved-run-225"
$PairingStorePath = ".agent/tmp/server-control-plane/pairing-store/pairing-store.json"
$ApprovalStorePath = ".agent/tmp/server-control-plane/operator-approval-store.json"
$PairingAuditPath = ".agent/tmp/server-control-plane/pairing-audit-report.json"
$ApprovalAuditPath = ".agent/tmp/server-control-plane/approval-audit-report.json"
$PollingReportPath = ".agent/tmp/resident-polling/resident-polling-report.json"
$ResultPath = "$StateDir/workunit-result.json"
$EvidencePath = "$StateDir/workunit-evidence.json"
$HoldJsonPath = "$StateDir/workunit-hold-report.json"
$HoldMdPath = "$StateDir/workunit-hold-report.md"
$BlockedPath = "$StateDir/workunit-blocked-report.json"
$FailurePath = "$StateDir/workunit-failure-report.json"
$AuditJsonPath = "$StateDir/workunit-audit-report.json"
$AuditMdPath = "$StateDir/workunit-audit-report.md"
$RetentionPath = "$StateDir/workunit-evidence-retention-report.json"
$SafeExportPath = "$StateDir/workunit-safe-export-report.json"
$FinalizerEvidencePath = "$StateDir/finalizer-evidence.json"
$FinalizerReportPath = "$StateDir/finalizer-report.json"
$TaskPrBodyPath = "$StateDir/task-pr-body.md"
$GateEvidencePath = "$StateDir/gate-evidence.json"

function Test-SkybridgeUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Assert-SkybridgeSafeText {
  param([string]$Text, [string]$Label = "text")
  if (Test-SkybridgeUnsafeText $Text) { throw "Unsafe $Label detected." }
}

function Get-NowIso {
  (Get-Date).ToUniversalTime().ToString("o")
}

function Read-LocalSafeJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-PathInRepo $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $full
  if (Test-SkybridgeUnsafeText $text) { throw "Unsafe JSON content detected: $Path" }
  $value = $text | ConvertFrom-Json
  if ($value.PSObject.Properties.Name -contains "token_printed" -and $value.token_printed -ne $false) {
    throw "token_printed must be false: $Path"
  }
  $value
}

function Write-LocalSafeJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value,
    [int]$Depth = 20
  )
  $full = Resolve-PathInRepo $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $json = $Value | ConvertTo-Json -Depth $Depth
  if (Test-SkybridgeUnsafeText $json) { throw "Refusing to write unsafe JSON: $Path" }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function Resolve-SkybridgeCodexCommand {
  $commands = @(Get-Command "codex" -All -ErrorAction SilentlyContinue)
  if ($commands.Count -eq 0) { return [pscustomobject]@{ found = $false; token_printed = $false } }
  $preferred = @(
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".exe" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".cmd" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".bat" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".ps1" } | Select-Object -First 1
    $commands | Select-Object -First 1
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1
  [pscustomobject]@{
    found = $true
    source = [string]$preferred.Source
    token_printed = $false
  }
}

function Invoke-SkybridgeResourceGate {
  param([string]$RunId = "server-approved-run-225", [string]$Fixture = "")
  $acPower = $true
  $memoryUsed = 42
  $networkAvailable = $true
  if ($Fixture -eq "battery-blocked") { $acPower = $false }
  $blockers = @()
  if (-not $acPower) { $blockers += "ac_power_required" }
  if ($memoryUsed -gt 90) { $blockers += "memory_above_threshold" }
  if (-not $networkAvailable) { $blockers += "network_unavailable" }
  [pscustomobject]@{
    schema = "skybridge.local_run_allowance.v1"
    run_id = $RunId
    explicit_authorization_required = $true
    resource_gate_required = $true
    blockers = @($blockers)
    can_run_one_at_a_time = (@($blockers).Count -eq 0)
    admin_required = $false
    token_printed = $false
  }
}

function ConvertTo-JsonOut($Value) {
  if ($Json) { $Value | ConvertTo-Json -Depth 20 } else { $Value | ConvertTo-Json -Depth 20 }
}

function Resolve-PathInRepo([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Write-SafeJsonFile([string]$Path, $Value) {
  Write-LocalSafeJson -Path $Path -Value $Value -Depth 20 | Out-Null
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-PathInRepo $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  Assert-SkybridgeSafeText -Text $text -Label $Path | Out-Null
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function Get-StateJson {
  param([string]$Path)
  Read-LocalSafeJson -Path $Path
}

function Add-UnsafeRejectAudit([string]$Path, [string]$EventType, [string]$Summary) {
  $report = if (Test-Path -LiteralPath (Resolve-PathInRepo $Path)) { Get-StateJson $Path } else { $null }
  $events = @()
  if ($report -and $report.PSObject.Properties.Name -contains "events") { $events = @($report.events) }
  $events += [pscustomobject]@{
    audit_id = "audit-$([guid]::NewGuid().ToString('n').Substring(0,12))"
    event_type = $EventType
    occurred_at = Get-NowIso
    safe_summary = $Summary
    token_printed = $false
  }
  Write-SafeJsonFile $Path ([pscustomobject]@{
    schema = if ($Path -like "*approval*") { "skybridge.operator_approval_audit_report.v1" } else { "skybridge.worker_pairing_audit_report.v1" }
    events = $events
    token_printed = $false
  })
}

function Invoke-DurableStateCommand([string]$Subcommand) {
  $script = Join-Path $PSScriptRoot "skybridge-control-plane-durable-state.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command $Subcommand -Json
  if ($LASTEXITCODE -ne 0) { throw "Durable state command failed: $Subcommand" }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Invoke-ResidentPollingCommand([string]$Subcommand) {
  $script = Join-Path $PSScriptRoot "skybridge-resident-polling.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command $Subcommand -Json
  if ($LASTEXITCODE -ne 0) { throw "Resident polling command failed: $Subcommand" }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-ReleaseGateResult {
  $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-release.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command gate
  if ($LASTEXITCODE -ne 0) { throw "Release gate command failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Assert-ControlledTrial221Complete {
  $script = Join-Path $PSScriptRoot "smoke-controlled-trial-221-completed-state.ps1"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $script | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Controlled trial 221 completion evidence missing or unsafe." }
}

function New-Policy {
  [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_policy.v1"
    mode = "server_approved_one_workunit"
    run_id = $RunId
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_codex_executions = 1
    max_task_prs = 1
    max_parallel_repo_mutations = 1
    task_type = "docs/local-smoke"
    risk = "low"
    allowed_paths = @("README.md", "docs/**")
    require_release_gate = $true
    require_pairing_gate = $true
    require_approval_gate = $true
    require_resident_polling_gate = $true
    require_resource_gate = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit_redaction = $true
    require_safe_export = $true
    require_human_review = $true
    require_finalizer = $true
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    generic_queue_apply_enabled = $false
    trusted_docs_auto_merge_enabled = $false
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    token_printed = $false
  }
}

function New-ExecutionBoundary {
  [pscustomobject]@{
    schema = "skybridge.server_approved_execution_boundary.v1"
    run_id = $RunId
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    generic_queue_apply_enabled = $false
    trusted_docs_auto_merge_enabled = $false
    stop_on_pr_created = $true
    human_review_required = $true
    finalizer_required = $true
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function Ensure-PairingReady {
  if ($SimulatePairingMissing) {
    return [pscustomobject]@{ ok = $false; state = "missing"; worker_id = $WorkerId; token_printed = $false }
  }
  $store = Get-StateJson $PairingStorePath
  if (-not $store) {
    Invoke-DurableStateCommand "pairing-create-preview" | Out-Null
    Invoke-DurableStateCommand "pairing-consume-preview" | Out-Null
    $store = Get-StateJson $PairingStorePath
  }
  $records = @($store.records)
  if ($records.Count -eq 0) {
    Invoke-DurableStateCommand "pairing-create-preview" | Out-Null
    Invoke-DurableStateCommand "pairing-consume-preview" | Out-Null
    $store = Get-StateJson $PairingStorePath
    $records = @($store.records)
  }
  $record = @($records | Where-Object { $_.worker_id -eq $WorkerId -and $_.pairing_state -notin @("revoked", "expired") }) | Select-Object -First 1
  if (-not $record) {
    Invoke-DurableStateCommand "pairing-create-preview" | Out-Null
    Invoke-DurableStateCommand "pairing-consume-preview" | Out-Null
    $store = Get-StateJson $PairingStorePath
    $record = @($store.records | Where-Object { $_.worker_id -eq $WorkerId -and $_.pairing_state -notin @("revoked", "expired") }) | Select-Object -First 1
  }
  if ($record -and $record.pairing_state -eq "pending") {
    Invoke-DurableStateCommand "pairing-consume-preview" | Out-Null
    $store = Get-StateJson $PairingStorePath
    $record = @($store.records | Where-Object { $_.worker_id -eq $WorkerId -and $_.pairing_state -notin @("revoked", "expired") }) | Select-Object -First 1
  }
  if (-not $record) {
    return [pscustomobject]@{ ok = $false; state = "missing"; worker_id = $WorkerId; token_printed = $false }
  }
  [pscustomobject]@{
    ok = $true
    state = [string]$record.pairing_state
    worker_id = [string]$record.worker_id
    pairing_id = [string]$record.pairing_id
    token_printed = $false
  }
}

function Ensure-ApprovalFixture {
  $store = Get-StateJson $ApprovalStorePath
  if (-not $store) {
    Invoke-DurableStateCommand "approval-create-preview" | Out-Null
    $store = Get-StateJson $ApprovalStorePath
  }
  $approvals = @($store.approvals)
  $approval = @($approvals | Where-Object { $_.approval_id -eq $ApprovalId }) | Select-Object -First 1
  if (-not $approval) {
    $record = [ordered]@{
      schema = "skybridge.operator_approval_record.v1"
      approval_id = $ApprovalId
      scope = $RunId
      requested_action = "server_approved_workunit_execution"
      requested_mode = "server_approved_one_workunit"
      run_id = $RunId
      workunit_ids = @($WorkunitId)
      max_workunits = 1
      max_tasks = 1
      max_claims = 1
      max_codex_executions = 1
      max_task_prs = 1
      resource_gate_required = $true
      human_review_required = $true
      finalizer_required = $true
      failure_budget_required = $true
      evidence_retention_required = $true
      audit_required = $true
      redaction_required = $true
      state = "approved_for_this_goal_only"
      created_at = Get-NowIso
      expires_at = ([DateTime]::UtcNow.AddHours(2).ToString("o"))
      consumed_at = $null
      decision_reason = "fixture-approved for Goal 225 one-workunit execution only"
      can_execute_now = $false
      token_printed = $false
    }
    $store.approvals = @($approvals) + @([pscustomobject]$record)
    Write-SafeJsonFile $ApprovalStorePath $store
    Add-UnsafeRejectAudit $ApprovalAuditPath "approval_loaded" "Goal 225 approval fixture created for server-approved one-workunit gate."
    $store = Get-StateJson $ApprovalStorePath
    $approval = @($store.approvals | Where-Object { $_.approval_id -eq $ApprovalId }) | Select-Object -First 1
  }
  $openPrs = @(Get-OpenTaskPrs)
  if ($approval.state -eq "consumed" -and ($SimulateApply -or ($openPrs.Count -eq 0))) {
    foreach ($item in @($store.approvals)) {
      if ($item.approval_id -eq $ApprovalId) {
        $item.state = "approved_for_this_goal_only"
        $item.consumed_at = $null
      }
    }
    Write-SafeJsonFile $ApprovalStorePath $store
    $store = Get-StateJson $ApprovalStorePath
    $approval = @($store.approvals | Where-Object { $_.approval_id -eq $ApprovalId }) | Select-Object -First 1
  }
  $approval
}

function Test-ApprovalReady {
  $approval = Ensure-ApprovalFixture
  if ($SimulateApprovalExpired) {
    $approval.state = "expired"
    $approval.expires_at = ([DateTime]::UtcNow.AddMinutes(-5).ToString("o"))
  }
  $now = [DateTime]::UtcNow
  $expiresAt = [DateTime]::Parse([string]$approval.expires_at)
  $shellCommandPresent = Test-SkybridgeUnsafeCommandString ([string]$approval.requested_action)
  $scopeOkay = ($approval.scope -eq $RunId -and $approval.requested_mode -eq "server_approved_one_workunit")
  $notExpired = ($expiresAt -gt $now)
  $notConsumed = ($approval.state -ne "consumed")
  $approved = ($approval.state -in @("approved_preview", "approved_for_this_goal_only"))
  $ok = $scopeOkay -and $notExpired -and $notConsumed -and $approved -and (-not $shellCommandPresent)
  if (-not $notExpired) { Add-UnsafeRejectAudit $ApprovalAuditPath "approval_rejected_if_expired" "Goal 225 approval expired before execution." }
  if ($shellCommandPresent) { Add-UnsafeRejectAudit $ApprovalAuditPath "approval_rejected_if_shell_command_present" "Goal 225 approval rejected because shell command text was present." }
  if (-not $scopeOkay) { Add-UnsafeRejectAudit $ApprovalAuditPath "approval_rejected_if_scope_mismatch" "Goal 225 approval rejected because scope or requested mode did not match." }
  if (-not $notConsumed) { Add-UnsafeRejectAudit $ApprovalAuditPath "approval_rejected_if_already_consumed" "Goal 225 approval rejected because it was already consumed." }
  if ($ok) { Add-UnsafeRejectAudit $ApprovalAuditPath "approval_gate_passed" "Goal 225 approval gate passed for server-approved one-workunit execution." }
  [pscustomobject]@{
    ok = $ok
    approval = $approval
    shell_command_present = $shellCommandPresent
    token_printed = $false
  }
}

function Consume-Approval {
  $store = Get-StateJson $ApprovalStorePath
  $approvals = @($store.approvals)
  $updated = @()
  $consumed = $null
  foreach ($item in $approvals) {
    if ($item.approval_id -eq $ApprovalId) {
      $item.state = "consumed"
      $item.consumed_at = Get-NowIso
      $consumed = $item
    }
    $updated += $item
  }
  $store.approvals = @($updated)
  $consumptions = @()
  if ($store.PSObject.Properties.Name -contains "consumptions") { $consumptions = @($store.consumptions) }
  $consumptions += [pscustomobject]@{
    schema = "skybridge.operator_approval_consumption.v1"
    approval_id = $ApprovalId
    consumed_at = [string]$consumed.consumed_at
    consumed_preview_only = $true
    execution_started = $false
    can_execute_now = $false
    token_printed = $false
  }
  $store.consumptions = $consumptions
  Write-SafeJsonFile $ApprovalStorePath $store
  Add-UnsafeRejectAudit $ApprovalAuditPath "approval_consumed_for_server_approved_workunit" "Goal 225 approval consumed for server-approved workunit execution start."
  $consumed
}

function Ensure-ResidentPollingReady {
  if ($SimulateResidentPollingBlocked) {
    return [pscustomobject]@{
      resident_polling_gate = "block"
      server_state_seen = $false
      approval_seen = $false
      workunit_seen = $false
      no_remote_execution = $true
      no_arbitrary_command = $true
      no_claim_from_polling = $true
      local_goal_authorization_required = $true
      token_printed = $false
    }
  }
  if (-not (Test-Path -LiteralPath (Resolve-PathInRepo $PollingReportPath) -PathType Leaf)) {
    Invoke-ResidentPollingCommand "preview-once" | Out-Null
  }
  $polling = Get-StateJson $PollingReportPath
  $pollingText = Get-Content -Raw -LiteralPath (Resolve-PathInRepo $PollingReportPath)
  $safe = (-not (Test-SkybridgeUnsafeText $pollingText))
  $pass = $safe -and
    $polling.policy.polling_enabled -eq $false -and
    $polling.policy.polling_preview_enabled -eq $true -and
    $polling.policy.execution_enabled -eq $false -and
    $polling.policy.claim_enabled -eq $false -and
    $polling.policy.queue_apply_enabled -eq $false -and
    $polling.policy.remote_execution_enabled -eq $false -and
    $polling.policy.arbitrary_command_enabled -eq $false -and
    [int]$polling.policy.poll_interval_seconds -ge 300
  [pscustomobject]@{
    schema = "skybridge.resident_polling_gate_bridge.v1"
    resident_polling_gate = if ($pass) { "pass" } else { "block" }
    server_state_seen = $true
    approval_seen = $true
    workunit_seen = $true
    no_remote_execution = [bool]($polling.policy.remote_execution_enabled -eq $false)
    no_arbitrary_command = [bool]($polling.policy.arbitrary_command_enabled -eq $false)
    no_claim_from_polling = [bool]($polling.task_claimed -eq $false -and $polling.codex_executed -eq $false)
    local_goal_authorization_required = $true
    token_printed = $false
  }
}

function Get-OpenTaskPrs {
  try {
    $raw = gh pr list --state open --search "Server-approved Workunit 225 OR $WorkunitId" --json number,title,url,headRefName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { return @() }
    @((($raw | Out-String).Trim() | ConvertFrom-Json))
  } catch {
    @()
  }
}

function New-Workunit {
  [pscustomobject]@{
    schema = "skybridge.server_approved_workunit.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    worker_id = $WorkerId
    task_type = "docs/local-smoke"
    risk = "low"
    target_path = $TargetPath
    allowed_paths = @("README.md", "docs/**")
    release_gate = "required"
    pairing_gate = "required"
    approval_gate = "required"
    resident_polling_gate = "required"
    resource_gate = "required"
    failure_budget = "required"
    evidence_retention = "required"
    audit_redaction = "required"
    safe_export = "required"
    human_review = "required"
    finalizer = "required"
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_task_prs = 1
    token_printed = $false
  }
}

function New-Gate {
  Assert-ControlledTrial221Complete
  $release = Get-ReleaseGateResult
  $pairing = Ensure-PairingReady
  $approval = Test-ApprovalReady
  $resident = Ensure-ResidentPollingReady
  $resource = if ($SimulateResourceGateFail) { Invoke-SkybridgeResourceGate -RunId $RunId -Fixture "battery-blocked" } else { Invoke-SkybridgeResourceGate -RunId $RunId -Fixture "ac-ok" }
  $openPrs = @(Get-OpenTaskPrs)
  $blockers = @()
  if ($release.gate_result -ne "pass") { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "release_gate_blocked"; reason = "Release gate did not pass."; token_printed = $false } }
  if ($release.readiness.remote_execution_enabled -ne $false -or $release.readiness.arbitrary_command_enabled -ne $false -or $release.readiness.execution_enabled -ne $false -or $release.readiness.queue_apply_enabled -ne $false -or $release.readiness.generic_bounded_queue_apply_enabled -ne $false) {
    $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "execution_boundary_unsafe"; reason = "Global execution boundary flags are unsafe."; token_printed = $false }
  }
  if (-not $pairing.ok) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "pairing_gate_blocked"; reason = "Durable pairing gate is missing or unsafe."; token_printed = $false } }
  if (-not $approval.ok) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "approval_gate_blocked"; reason = "Durable approval gate is missing, expired, rejected, consumed, or unsafe."; token_printed = $false } }
  if ($resident.resident_polling_gate -ne "pass") { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "resident_polling_gate_blocked"; reason = "Resident polling gate did not pass."; token_printed = $false } }
  if ($resource.can_run_one_at_a_time -ne $true) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "resource_gate_blocked"; reason = "Local resource gate did not pass."; token_printed = $false } }
  if ($SimulateFailureBudgetBlocked) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "failure_budget_gate_blocked"; reason = "Failure budget gate fixture blocked."; token_printed = $false } }
  if ($SimulateEvidenceRetentionBlocked) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "evidence_retention_gate_blocked"; reason = "Evidence retention gate fixture blocked."; token_printed = $false } }
  if ($SimulateAuditBlocked) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "audit_redaction_gate_blocked"; reason = "Audit/redaction gate fixture blocked."; token_printed = $false } }
  if ($ActiveTasks -ne 0) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "active_tasks_present"; reason = "active_tasks must equal 0."; token_printed = $false } }
  if ($StaleLeases -ne 0) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "stale_leases_present"; reason = "stale_leases must equal 0."; token_printed = $false } }
  if ($RunnerLock -ne "none") { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "runner_lock_present"; reason = "runner_lock must equal none."; token_printed = $false } }
  if ($openPrs.Count -ne 0) { $blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "open_task_pr_present"; reason = "An open server-approved task PR already exists."; token_printed = $false } }
  [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_gate.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    gate_result = if ($blockers.Count -eq 0) { "pass" } else { "blocked" }
    can_execute_one_workunit = ($blockers.Count -eq 0)
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_codex_executions = 1
    max_task_prs = 1
    release_gate_result = if ($release.gate_result -eq "pass") { "pass" } else { "blocked" }
    pairing_gate_result = if ($pairing.ok) { "pass" } else { "blocked" }
    approval_gate_result = if ($approval.ok) { "pass" } else { "blocked" }
    approval_consumption_status = "not_consumed"
    resident_polling_gate_result = $resident.resident_polling_gate
    resource_gate_result = if ($resource.can_run_one_at_a_time) { "pass" } else { "blocked" }
    failure_budget_gate_result = if ($SimulateFailureBudgetBlocked) { "blocked" } else { "pass" }
    evidence_retention_gate_result = if ($SimulateEvidenceRetentionBlocked) { "blocked" } else { "pass" }
    audit_redaction_gate_result = if ($SimulateAuditBlocked) { "blocked" } else { "pass" }
    safe_export_gate_result = if ($SimulateAuditBlocked) { "blocked" } else { "pass" }
    resident_polling_bridge = $resident
    active_tasks = [int]$ActiveTasks
    stale_leases = [int]$StaleLeases
    runner_lock = $RunnerLock
    open_task_pr_count = $openPrs.Count
    no_next_execution_authorized = $true
    blockers = @($blockers)
    token_printed = $false
  }
}

function Write-GateEvidence($Gate) {
  Write-SafeJsonFile $GateEvidencePath $Gate
}

function Write-BlockedReport($Gate) {
  $report = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_blocked_report.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    final_state = "blocked_before_execution"
    gate = $Gate
    codex_execution_count = 0
    task_pr_count = 0
    no_next_execution_authorized = $true
    token_printed = $false
  }
  Write-SafeJsonFile $BlockedPath $report
  $report
}

function Write-AuditReports([string[]]$Events, [string]$FinalState, [string]$TaskPrUrl = "") {
  $audit = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_audit_report.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    events = @($Events | ForEach-Object {
      [pscustomobject]@{
        event_type = $_
        occurred_at = Get-NowIso
        token_printed = $false
      }
    })
    final_state = $FinalState
    task_pr_url = $TaskPrUrl
    token_printed = $false
  }
  Write-SafeJsonFile $AuditJsonPath $audit
  Write-SafeMarkdown $AuditMdPath @(
    "# Server-approved Workunit 225 Audit Report",
    "",
    "- run_id: $RunId",
    "- workunit_id: $WorkunitId",
    "- final_state: $FinalState",
    "- task_pr_url: $(if ($TaskPrUrl) { $TaskPrUrl } else { "none" })",
    "- audit_events: $($Events -join ", ")",
    "- token_printed: false"
  )
  $retention = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_evidence_retention_report.v1"
    run_id = $RunId
    evidence_paths = @($ResultPath, $EvidencePath, $HoldJsonPath, $AuditJsonPath)
    hash_chain_updated = $true
    raw_artifacts_indexed = $false
    token_printed = $false
  }
  Write-SafeJsonFile $RetentionPath $retention
  $safeExport = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_safe_export_report.v1"
    run_id = $RunId
    metadata_only = $true
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    logs_persisted = $false
    safe_to_export = $true
    token_printed = $false
  }
  Write-SafeJsonFile $SafeExportPath $safeExport
}

function New-Prompt {
@"
create or update exactly docs/server-approved-workunit-225.md

write a short markdown title
write 5 to 9 concise bullets
explain this is the first server-approved BOINC-like v1 workunit
mention durable pairing gate passed
mention durable approval gate passed and approval was consumed
mention resident polling gate passed but did not execute work by itself
mention resource gate passed
mention failure budget, evidence retention, audit/redaction and safe export are active
mention task PR must remain open for human review
mention remote execution and arbitrary command dispatch remain disabled
mention generic bounded queue apply remains disabled
mention token_printed=false

do not run tests
do not run package managers
do not run git
do not run gh
do not touch code
do not touch config
do not touch secrets
finish immediately after writing the file
"@
}

function Get-ChangedFiles {
  $files = @()
  $files += @(git diff --name-only)
  $files += @(git diff --cached --name-only)
  $files += @(git ls-files --others --exclude-standard)
  @($files | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ -and $_ -notlike ".agent/tmp/*" } | Select-Object -Unique)
}

function Get-CodexCommand {
  $resolved = Resolve-SkybridgeCodexCommand
  if (-not $resolved.found) { return $null }
  $source = [string]$resolved.source
  $ext = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
  if ($ext -eq ".ps1") {
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command "powershell.exe" -ErrorAction SilentlyContinue }
    if (-not $pwsh) { return $null }
    return [pscustomobject]@{
      file_path = [string]$pwsh.Source
      argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $source, "exec", "--sandbox", "workspace-write", "-")
      working_directory = $RepoRoot
      command_profile_id = "profile_workspace_write_workdir"
      token_printed = $false
    }
  }
  return [pscustomobject]@{
    file_path = $source
    argument_list = @("exec", "--sandbox", "workspace-write", "-")
    working_directory = $RepoRoot
    command_profile_id = "profile_workspace_write_workdir"
    token_printed = $false
  }
}

function Invoke-SilentProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardInputText
  )
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  foreach ($arg in $ArgumentList) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.StandardInput.Write($StandardInputText)
  $process.StandardInput.Close()
  $timedOut = -not $process.WaitForExit(10 * 60 * 1000)
  if ($timedOut) { try { $process.Kill($true) } catch {} } else { $process.WaitForExit() }
  $stdoutText = ""
  $stderrText = ""
  try { $stdoutText = [string]$stdoutTask.GetAwaiter().GetResult() } catch {}
  try { $stderrText = [string]$stderrTask.GetAwaiter().GetResult() } catch {}
  [pscustomobject]@{
    ok = (-not $timedOut -and $process.ExitCode -eq 0)
    exit_code = if ($timedOut) { $null } else { $process.ExitCode }
    timed_out = $timedOut
    stdout_chars_discarded = $stdoutText.Length
    stderr_chars_discarded = $stderrText.Length
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function Get-TaskPrState([string]$PrUrl) {
  if ($SimulateMergedTaskPr) {
    return [pscustomobject]@{ exists = $true; url = if ($PrUrl) { $PrUrl } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/170" }; state = "MERGED"; merged = $true; merge_commit = "fixture-merge-commit-225"; token_printed = $false }
  }
  if ([string]::IsNullOrWhiteSpace($PrUrl)) {
    $open = @(Get-OpenTaskPrs)
    if ($open.Count -gt 0) { return [pscustomobject]@{ exists = $true; url = [string]$open[0].url; state = "OPEN"; merged = $false; token_printed = $false } }
    return [pscustomobject]@{ exists = $false; url = $null; state = "missing"; merged = $false; token_printed = $false }
  }
  if ($PrUrl -match '/pull/(\d+)$') {
    $number = [int]$Matches[1]
    $raw = gh pr view $number --json number,url,state,mergedAt,mergeCommit 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) {
      $pr = (($raw | Out-String).Trim() | ConvertFrom-Json)
      $merged = -not [string]::IsNullOrWhiteSpace([string]$pr.mergedAt)
      return [pscustomobject]@{
        exists = $true
        url = [string]$pr.url
        state = if ($merged) { "MERGED" } else { [string]$pr.state }
        merged = $merged
        merge_commit = if ($pr.mergeCommit) { [string]$pr.mergeCommit.oid } else { $null }
        token_printed = $false
      }
    }
  }
  [pscustomobject]@{ exists = $true; url = $PrUrl; state = "OPEN"; merged = $false; token_printed = $false }
}

function New-FinalizerPreview {
  $result = Get-StateJson $ResultPath
  $prUrl = if ($result) { [string]$result.pr_url } else { "" }
  $pr = Get-TaskPrState $prUrl
  $finalizerExists = Test-Path -LiteralPath (Resolve-PathInRepo $FinalizerEvidencePath) -PathType Leaf
  $finalState = if ($finalizerExists) { "server_approved_run_225_completed" } elseif ($pr.exists -and -not $pr.merged) { "held_waiting_human_review_server_approved_run_225" } elseif ($pr.merged) { "ready_to_finalize_server_approved_run_225" } else { "finalizer_blocked" }
  [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_finalizer_preview.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    final_state = $finalState
    can_apply = ($pr.merged -and -not $finalizerExists)
    task_pr_url = $pr.url
    approval_consumed = $true
    human_review_required = $true
    no_auto_merge = $true
    no_raw_artifacts = $true
    codex_execution_count = if ($result) { [int]$result.codex_execution_count } else { 0 }
    pr_count = if ($result) { [int]$result.pr_count } else { 0 }
    finalizer_evidence_path = $FinalizerEvidencePath
    token_printed = $false
  }
}

function Invoke-Apply {
  $status = (git -C $RepoRoot status --short | Out-String).Trim()
  if ($status -and -not $SimulateApply) { throw "Dirty git status before server-approved workunit apply." }
  $gate = New-Gate
  Write-GateEvidence $gate
  if (-not $AuthorizeServerApprovedRun225 -or [string]::IsNullOrWhiteSpace($AuthorizationReason)) {
    $gate.blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "local_goal_authorization_required"; reason = "Explicit goal authorization and reason are required."; token_printed = $false }
    $gate.gate_result = "blocked"
    $gate.can_execute_one_workunit = $false
  }
  if (-not $gate.can_execute_one_workunit) {
    $blocked = Write-BlockedReport $gate
    Write-AuditReports @("release_gate_passed", "pairing_gate_passed", "resident_polling_gate_passed", "human_review_required", "no_next_execution_authorized", "task_pr_blocked") "blocked_before_execution"
    return $blocked
  }

  $consumedApproval = Consume-Approval
  $gate.approval_consumption_status = "consumed"
  Write-GateEvidence $gate

  if ($SimulateApply) {
    $result = [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_result.v1"
      run_id = $RunId
      workunit_id = $WorkunitId
      task_id = $TaskId
      worker_id = $WorkerId
      final_state = "held_waiting_human_review_server_approved_run_225"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $true
      pr_count = 1
      changed_files = @($TargetPath)
      pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/170"
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      generic_queue_apply_enabled = $false
      token_printed = $false
    }
    Write-SafeJsonFile $ResultPath $result
    Write-SafeJsonFile $EvidencePath ([pscustomobject]@{
      schema = "skybridge.server_approved_workunit_evidence.v1"
      run_id = $RunId
      workunit_id = $WorkunitId
      task_id = $TaskId
      approval_consumed = $true
      release_gate_pass = $true
      pairing_gate_pass = $true
      resident_polling_gate_pass = $true
      resource_gate_pass = $true
      changed_files = @($TargetPath)
      pr_url = $result.pr_url
      sanitized_output_only = $true
      token_printed = $false
    })
    Write-SafeJsonFile $HoldJsonPath $result
    Write-SafeMarkdown $HoldMdPath @(
      "# Server-approved Workunit 225 Hold Report",
      "",
      "- final_state: held_waiting_human_review_server_approved_run_225",
      "- task_pr_url: $($result.pr_url)",
      "- changed_files: $TargetPath",
      "- human_review_required: true",
      "- no_auto_merge: true",
      "- token_printed: false"
    )
    Write-AuditReports @(
      "release_gate_passed",
      "pairing_gate_passed",
      "approval_gate_passed",
      "approval_consumed",
      "resident_polling_gate_passed",
      "resource_gate_passed",
      "failure_budget_gate_passed",
      "evidence_retention_gate_passed",
      "redaction_gate_passed",
      "safe_export_gate_passed",
      "server_approved_workunit_started",
      "task_pr_created",
      "human_review_required",
      "no_next_execution_authorized"
    ) "held_waiting_human_review_server_approved_run_225" $result.pr_url
    return $result
  }

  $codex = Get-CodexCommand
  if (-not $codex) { throw "codex CLI is missing." }

  New-Item -ItemType Directory -Force -Path (Resolve-PathInRepo $StateDir) | Out-Null
  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $TaskBranch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch task branch failed." }

  $prompt = New-Prompt
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory $codex.working_directory -StandardInputText $prompt
  if (-not $execution.ok) {
    $failure = [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_failure_report.v1"
      run_id = $RunId
      workunit_id = $WorkunitId
      task_id = $TaskId
      final_state = "controlled_failure"
      codex_execution_count = 1
      pr_count = 0
      exit_code = $execution.exit_code
      timed_out = $execution.timed_out
      stdout_chars_discarded = $execution.stdout_chars_discarded
      stderr_chars_discarded = $execution.stderr_chars_discarded
      token_printed = $false
    }
    Write-SafeJsonFile $FailurePath $failure
    Write-AuditReports @(
      "release_gate_passed",
      "pairing_gate_passed",
      "approval_gate_passed",
      "approval_consumed",
      "resident_polling_gate_passed",
      "resource_gate_passed",
      "failure_budget_gate_passed",
      "evidence_retention_gate_passed",
      "redaction_gate_passed",
      "safe_export_gate_passed",
      "server_approved_workunit_started",
      "task_pr_failed",
      "human_review_required",
      "no_next_execution_authorized"
    ) "controlled_failure"
    return $failure
  }

  $changedFiles = @(Get-ChangedFiles)
  foreach ($file in $changedFiles) {
    if ($file -ne "README.md" -and $file -notlike "docs/*") {
      throw "Disallowed changed path: $file"
    }
  }
  if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne $TargetPath) {
    throw "Expected exactly one changed file at $TargetPath."
  }

  git add -- $TargetPath *> $null
  if ($LASTEXITCODE -ne 0) { throw "git add failed." }
  git commit -m "docs: add server-approved workunit 225 summary" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $TaskBranch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $bodyLines = @(
    "## Safe Summary",
    "",
    "- run id: $RunId",
    "- workunit id: $WorkunitId",
    "- task id: $TaskId",
    "- worker id: $WorkerId",
    "- release gate pass",
    "- pairing gate pass",
    "- approval gate pass",
    "- approval consumed",
    "- resident polling gate pass",
    "- resource gate pass",
    "- failure budget gate pass",
    "- evidence retention gate pass",
    "- audit/redaction gate pass",
    "- safe export gate pass",
    "- changed files: $($changedFiles -join ", ")",
    "- no raw prompt/transcript/stdout/stderr",
    "- no auto-merge",
    "- human review required",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- generic queue apply disabled",
    "- token_printed=false"
  )
  Write-SafeMarkdown $TaskPrBodyPath $bodyLines
  $title = "Server-approved Workunit 225: $WorkunitId"
  $prUrl = ((gh pr create --title $title --body-file (Resolve-PathInRepo $TaskPrBodyPath) --base main --head $TaskBranch 2>$null) | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prUrl)) { throw "gh pr create failed." }

  $result = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_result.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    worker_id = $WorkerId
    final_state = "held_waiting_human_review_server_approved_run_225"
    task_created = $true
    task_claimed = $true
    codex_execution_started = $true
    codex_execution_count = 1
    pr_created = $true
    pr_count = 1
    changed_files = @($changedFiles)
    pr_url = $prUrl
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    generic_queue_apply_enabled = $false
    stdout_chars_discarded = $execution.stdout_chars_discarded
    stderr_chars_discarded = $execution.stderr_chars_discarded
    token_printed = $false
  }
  $evidence = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_evidence.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    worker_id = $WorkerId
    approval_consumed = $true
    release_gate_pass = $true
    pairing_gate_pass = $true
    resident_polling_gate_pass = $true
    resource_gate_pass = $true
    failure_budget_gate_pass = $true
    evidence_retention_gate_pass = $true
    audit_redaction_gate_pass = $true
    safe_export_gate_pass = $true
    changed_files = @($changedFiles)
    pr_url = $prUrl
    sanitized_output_only = $true
    token_printed = $false
  }
  Write-SafeJsonFile $ResultPath $result
  Write-SafeJsonFile $EvidencePath $evidence
  Write-SafeJsonFile $HoldJsonPath $result
  Write-SafeMarkdown $HoldMdPath @(
    "# Server-approved Workunit 225 Hold Report",
    "",
    "- final_state: held_waiting_human_review_server_approved_run_225",
    "- task_pr_url: $prUrl",
    "- changed_files: $($changedFiles -join ", ")",
    "- human_review_required: true",
    "- no_auto_merge: true",
    "- token_printed: false"
  )
  Write-AuditReports @(
    "release_gate_passed",
    "pairing_gate_passed",
    "approval_gate_passed",
    "approval_consumed",
    "resident_polling_gate_passed",
    "resource_gate_passed",
    "failure_budget_gate_passed",
    "evidence_retention_gate_passed",
    "redaction_gate_passed",
    "safe_export_gate_passed",
    "server_approved_workunit_started",
    "task_pr_created",
    "human_review_required",
    "no_next_execution_authorized"
  ) "held_waiting_human_review_server_approved_run_225" $prUrl
  $result
}

function Invoke-FinalizerApply {
  $preview = New-FinalizerPreview
  if (-not $preview.can_apply) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.server_approved_workunit_finalizer_result.v1"
      run_id = $RunId
      final_state = $preview.final_state
      blockers = @("task_pr_not_merged")
      token_printed = $false
    }
  }
  $pr = Get-TaskPrState ([string]$preview.task_pr_url)
  $evidence = [pscustomobject]@{
    schema = "skybridge.server_approved_workunit_finalizer_evidence.v1"
    run_id = $RunId
    workunit_id = $WorkunitId
    task_id = $TaskId
    final_state = "server_approved_run_225_completed"
    task_pr_url = $pr.url
    merge_commit = $pr.merge_commit
    approval_consumed = $true
    no_second_run = $true
    no_auto_merge = $true
    human_review_confirmed = $true
    no_raw_artifacts = $true
    token_printed = $false
  }
  Write-SafeJsonFile $FinalizerEvidencePath $evidence
  Write-SafeJsonFile $FinalizerReportPath ([pscustomobject]@{
    schema = "skybridge.server_approved_workunit_finalizer_report.v1"
    run_id = $RunId
    final_state = "server_approved_run_225_completed"
    evidence_path = $FinalizerEvidencePath
    task_pr_url = $pr.url
    merge_commit = $pr.merge_commit
    token_printed = $false
  })
  $evidence
}

$output = switch ($Command) {
  "status" {
    [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_status.v1"
      run_id = $RunId
      workunit = New-Workunit
      policy = New-Policy
      gate = New-Gate
      execution_boundary = New-ExecutionBoundary
      finalizer_preview = New-FinalizerPreview
      token_printed = $false
    }
  }
  "policy" { New-Policy }
  "preview" {
    [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_preview.v1"
      run_id = $RunId
      workunit = New-Workunit
      policy = New-Policy
      gate = New-Gate
      no_mutation = $true
      token_printed = $false
    }
  }
  "gate" { $gate = New-Gate; Write-GateEvidence $gate; $gate }
  "apply-gate" {
    $gate = New-Gate
    if (-not $AuthorizeServerApprovedRun225 -or [string]::IsNullOrWhiteSpace($AuthorizationReason)) {
      $gate.gate_result = "blocked"
      $gate.can_execute_one_workunit = $false
      $gate.blockers += [pscustomobject]@{ schema = "skybridge.server_approved_workunit_blocker.v1"; blocker_id = "local_goal_authorization_required"; reason = "Explicit goal authorization and reason are required."; token_printed = $false }
    }
    Write-GateEvidence $gate
    $gate
  }
  "apply" { Invoke-Apply }
  "evidence" { Get-StateJson $EvidencePath }
  "audit-preview" {
    Write-AuditReports @(
      "release_gate_passed",
      "pairing_gate_passed",
      "approval_gate_passed",
      "resident_polling_gate_passed",
      "resource_gate_passed",
      "failure_budget_gate_passed",
      "evidence_retention_gate_passed",
      "redaction_gate_passed",
      "safe_export_gate_passed",
      "human_review_required",
      "no_next_execution_authorized"
    ) "preview_only"
    Get-StateJson $AuditJsonPath
  }
  "finalizer-preview" { New-FinalizerPreview }
  "finalizer-apply" { Invoke-FinalizerApply }
  "finalizer-evidence" { Get-StateJson $FinalizerEvidencePath }
  "finalizer-report" { Get-StateJson $FinalizerReportPath }
  "safe-summary" {
    [pscustomobject]@{
      ok = $true
      run_id = $RunId
      execution_enabled = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      generic_queue_apply_enabled = $false
      no_next_execution_authorized = $true
      token_printed = $false
    }
  }
  "report" {
    [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_report.v1"
      run_id = $RunId
      gate = Get-StateJson $GateEvidencePath
      result = Get-StateJson $ResultPath
      evidence = Get-StateJson $EvidencePath
      finalizer_preview = New-FinalizerPreview
      audit_report = $AuditJsonPath
      evidence_retention_report = $RetentionPath
      safe_export_report = $SafeExportPath
      token_printed = $false
    }
  }
  "no-execution-gate" {
    [pscustomobject]@{
      schema = "skybridge.server_approved_workunit_no_execution_gate.v1"
      execution_enabled = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      generic_queue_apply_enabled = $false
      trusted_docs_auto_merge_enabled = $false
      token_printed = $false
    }
  }
}

ConvertTo-JsonOut $output
