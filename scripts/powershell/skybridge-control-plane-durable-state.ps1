param(
  [ValidateSet(
    "pairing-create-preview",
    "pairing-consume-preview",
    "pairing-list",
    "pairing-revoke-preview",
    "pairing-expire-fixture",
    "pairing-safe-summary",
    "pairing-store-report",
    "approval-create-preview",
    "approval-approve-preview",
    "approval-reject-preview",
    "approval-expire-fixture",
    "approval-consume-preview",
    "approval-list",
    "approval-audit-summary",
    "approval-store-report",
    "security-rejection-fixtures",
    "goal-223-report"
  )]
  [string]$Command = "pairing-safe-summary",
  [string]$PairingId = "pairing-goal-223-preview",
  [string]$ApprovalId = "approval-goal-223-preview",
  [string]$WorkerId = "laptop-zenbookduo",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ControlDir = Join-Path $RepoRoot ".agent\tmp\server-control-plane"
$PairingDir = Join-Path $ControlDir "pairing-store"
$PairingStorePath = Join-Path $PairingDir "pairing-store.json"
$ApprovalStorePath = Join-Path $ControlDir "operator-approval-store.json"
$PairingAuditPath = Join-Path $ControlDir "pairing-audit-report.json"
$ApprovalAuditPath = Join-Path $ControlDir "approval-audit-report.json"
$Goal223JsonPath = Join-Path $ControlDir "goal-223-report.json"
$Goal223MdPath = Join-Path $ControlDir "goal-223-report.md"

function New-Now {
  return (Get-Date).ToUniversalTime().ToString("o")
}

function New-FutureIso([int]$Minutes = 60) {
  return (Get-Date).ToUniversalTime().AddMinutes($Minutes).ToString("o")
}

function ConvertTo-Sha256Hex([string]$Value) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Ensure-Dirs {
  New-Item -ItemType Directory -Force -Path $PairingDir | Out-Null
}

function Write-SafeJson($Value, [string]$Path) {
  $text = $Value | ConvertTo-Json -Depth 20
  Assert-SafeText $text
  $text | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Assert-SafeText([string]$Text) {
  $patterns = @(
    '"token_printed"\s*:\s*true',
    'raw_pairing_code"\s*:',
    'raw_token"\s*:',
    'Authorization\s*:',
    'Bearer\s+[A-Za-z0-9_.-]{8,}',
    'BEGIN [A-Z ]*PRIVATE KEY',
    '"Cookie"\s*:',
    '"cookies"\s*:',
    '"env"\s*:\s*\{',
    '"environment"\s*:\s*\{',
    '"shell_command"\s*:'
  )
  foreach ($pattern in $patterns) {
    if ($Text -match $pattern) { throw "Unsafe payload rejected: $pattern" }
  }
}

function New-PairingStore {
  [ordered]@{
    schema = "skybridge.worker_pairing_store.v1"
    store_path_redacted = ".agent/tmp/server-control-plane/pairing-store/pairing-store.json"
    records = @()
    revocations = @()
    expiries = @()
    raw_pairing_code_persisted = $false
    raw_token_persisted = $false
    execution_enabled = $false
    token_printed = $false
  }
}

function Read-PairingStore {
  Ensure-Dirs
  if (-not (Test-Path -LiteralPath $PairingStorePath)) {
    $store = New-PairingStore
    Write-SafeJson $store $PairingStorePath
    return $store
  }
  $text = Get-Content -Raw -LiteralPath $PairingStorePath
  Assert-SafeText $text
  return ($text | ConvertFrom-Json)
}

function Save-PairingStore($Store) {
  $Store.raw_pairing_code_persisted = $false
  $Store.raw_token_persisted = $false
  $Store.execution_enabled = $false
  $Store.token_printed = $false
  Write-SafeJson $Store $PairingStorePath
}

function Add-Audit([string]$Kind, [string]$EventType, [string]$SubjectId, [string]$Summary) {
  Ensure-Dirs
  $path = if ($Kind -eq "pairing") { $PairingAuditPath } else { $ApprovalAuditPath }
  $items = @()
  if (Test-Path -LiteralPath $path) {
    $items = @((Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).events)
  }
  $items += [ordered]@{
    schema = if ($Kind -eq "pairing") { "skybridge.worker_pairing_audit_record.v1" } else { "skybridge.operator_approval_audit_record.v1" }
    audit_id = "$Kind-audit-$([Guid]::NewGuid().ToString("n").Substring(0, 12))"
    pairing_id = if ($Kind -eq "pairing") { $SubjectId } else { $null }
    approval_id = if ($Kind -eq "approval") { $SubjectId } else { $null }
    event_type = $EventType
    occurred_at = New-Now
    safe_summary = $Summary
    token_printed = $false
  }
  $report = [ordered]@{
    schema = if ($Kind -eq "pairing") { "skybridge.worker_pairing_audit_report.v1" } else { "skybridge.operator_approval_audit_report.v1" }
    events = $items
    execution_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
  Write-SafeJson $report $path
}

function Find-RecordIndex($Records, [string]$Id, [string]$IdField) {
  for ($i = 0; $i -lt @($Records).Count; $i++) {
    if ($Records[$i].$IdField -eq $Id) { return $i }
  }
  return -1
}

function New-PairingRecord {
  $created = New-Now
  $codeFixture = "preview-pairing-code-1234"
  [ordered]@{
    schema = "skybridge.worker_pairing_record.v1"
    pairing_id = $PairingId
    worker_id = $WorkerId
    device_id_hash = "sha256-local-device-fixture"
    repo = "skybridge-agent-hub"
    display_name = "Zenbook Duo local resident preview"
    created_at = $created
    expires_at = New-FutureIso 60
    revoked_at = $null
    pairing_state = "pending"
    raw_pairing_code_persisted = $false
    pairing_code_hash = "sha256:$(ConvertTo-Sha256Hex $codeFixture)"
    pairing_code_preview_last4 = "1234"
    capabilities = @("heartbeat", "resident-polling-preview")
    resident_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-PairingReport($Store) {
  $records = @($Store.records)
  [ordered]@{
    schema = "skybridge.worker_pairing_store_report.v1"
    pairing_count = $records.Count
    paired_count = @($records | Where-Object pairing_state -eq "paired").Count
    expired_count = @($records | Where-Object pairing_state -eq "expired").Count
    revoked_count = @($records | Where-Object pairing_state -eq "revoked").Count
    raw_pairing_code_persisted = $false
    raw_token_persisted = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-ApprovalStore {
  [ordered]@{
    schema = "skybridge.operator_approval_store.v1"
    store_path_redacted = ".agent/tmp/server-control-plane/operator-approval-store.json"
    approvals = @()
    consumptions = @()
    expiries = @()
    audit = @()
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function Read-ApprovalStore {
  Ensure-Dirs
  if (-not (Test-Path -LiteralPath $ApprovalStorePath)) {
    $store = New-ApprovalStore
    Write-SafeJson $store $ApprovalStorePath
    return $store
  }
  $text = Get-Content -Raw -LiteralPath $ApprovalStorePath
  Assert-SafeText $text
  return ($text | ConvertFrom-Json)
}

function Save-ApprovalStore($Store) {
  $Store.execution_enabled = $false
  $Store.queue_apply_enabled = $false
  $Store.remote_execution_enabled = $false
  $Store.arbitrary_command_enabled = $false
  $Store.token_printed = $false
  Write-SafeJson $Store $ApprovalStorePath
}

function New-ApprovalRecord {
  [ordered]@{
    schema = "skybridge.operator_approval_record.v1"
    approval_id = $ApprovalId
    scope = "skybridge-agent-hub/local-preview"
    requested_action = "resident_polling_preview"
    requested_mode = "preview"
    run_id = "goal-223-224-preview"
    workunit_ids = @()
    max_workunits = 0
    max_tasks = 0
    max_claims = 0
    max_codex_executions = 0
    max_task_prs = 0
    resource_gate_required = $true
    human_review_required = $true
    finalizer_required = $true
    failure_budget_required = $true
    evidence_retention_required = $true
    audit_required = $true
    redaction_required = $true
    state = "pending"
    created_at = New-Now
    expires_at = New-FutureIso 60
    consumed_at = $null
    decision_reason = "preview-only durable approval state; no execution side effects"
    can_execute_now = $false
    token_printed = $false
  }
}

function New-ApprovalReport($Store) {
  $approvals = @($Store.approvals)
  [ordered]@{
    schema = "skybridge.operator_approval_store_report.v1"
    approval_count = $approvals.Count
    pending_count = @($approvals | Where-Object state -eq "pending").Count
    approved_preview_count = @($approvals | Where-Object state -eq "approved_preview").Count
    rejected_count = @($approvals | Where-Object state -eq "rejected").Count
    expired_count = @($approvals | Where-Object state -eq "expired").Count
    consumed_count = @($approvals | Where-Object state -eq "consumed").Count
    can_execute_now = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function Invoke-SecurityRejectionFixtures {
  $cases = @(
    @{ name = "raw_pairing_code_persistence_attempt"; payload = @{ raw_pairing_code = "preview-pairing-code-0000" } },
    @{ name = "raw_token_persistence_attempt"; payload = @{ raw_token = "token-fixture" } },
    @{ name = "token_printed_true_payload"; payload = @{ token_printed = $true } },
    @{ name = "authorization_header_payload"; payload = @{ Authorization = "Bearer fixture-token" } },
    @{ name = "bearer_token_payload"; payload = @{ value = "Bearer fixture-token" } },
    @{ name = "private_key_payload"; payload = @{ value = "-----BEGIN PRIVATE KEY-----" } },
    @{ name = "cookie_payload"; payload = @{ Cookie = "session=fixture" } },
    @{ name = "environment_dump_payload"; payload = @{ env = @{ PATH = "fixture" } } },
    @{ name = "shell_command_text_in_approval"; payload = @{ shell_command = "echo unsafe" } },
    @{ name = "execution_enabled_true_pairing"; payload = @{ execution_enabled = $true } },
    @{ name = "queue_apply_enabled_true_pairing"; payload = @{ queue_apply_enabled = $true } },
    @{ name = "remote_execution_enabled_true"; payload = @{ remote_execution_enabled = $true } },
    @{ name = "arbitrary_command_enabled_true"; payload = @{ arbitrary_command_enabled = $true } }
  )
  foreach ($case in $cases) {
    $jsonText = $case.payload | ConvertTo-Json -Depth 10
    $rejected = $false
    try {
      Assert-SafeText $jsonText
      if ($jsonText -match '"(execution_enabled|queue_apply_enabled|remote_execution_enabled|arbitrary_command_enabled)"\s*:\s*true') { throw "enabled flag rejected" }
    } catch {
      $rejected = $true
    }
    if (-not $rejected) { throw "Unsafe fixture was not rejected: $($case.name)" }
    Add-Audit "pairing" "unsafe_payload_rejected" $PairingId $case.name
    Add-Audit "approval" "unsafe_payload_rejected" $ApprovalId $case.name
  }
  [ordered]@{
    ok = $true
    rejected_case_count = $cases.Count
    remote_execution_rejected = $true
    arbitrary_command_rejected = $true
    token_printed = $false
  }
}

function Write-Goal223Report {
  $pairingStore = Read-PairingStore
  $approvalStore = Read-ApprovalStore
  $security = Invoke-SecurityRejectionFixtures
  $report = [ordered]@{
    schema = "skybridge.goal_223_report.v1"
    pairing_store_status = "durable_local_preview"
    approval_store_status = "durable_local_preview"
    security_rejection_coverage = $security.rejected_case_count
    audit_events = @(
      "pairing_created_preview",
      "pairing_consumed_preview",
      "pairing_expired_preview",
      "pairing_revoked_preview",
      "approval_requested_preview",
      "approval_approved_preview",
      "approval_rejected_preview",
      "approval_expired_preview",
      "approval_consumed_preview",
      "unsafe_payload_rejected",
      "remote_execution_rejected",
      "arbitrary_command_rejected"
    )
    ui_panels = @("Pairing store list", "Pairing record detail", "Approval store list", "Approval detail", "Approval audit state", "Disabled execution banners")
    pairing_report = New-PairingReport $pairingStore
    approval_report = New-ApprovalReport $approvalStore
    execution_disabled = $true
    remote_execution_disabled = $true
    arbitrary_command_disabled = $true
    token_printed = $false
    ready_for_goal_224 = $true
  }
  Write-SafeJson $report $Goal223JsonPath
  @(
    "# Goal 223 Report",
    "",
    "- pairing_store_status: durable_local_preview",
    "- approval_store_status: durable_local_preview",
    "- security_rejection_coverage: $($security.rejected_case_count)",
    "- execution_disabled: true",
    "- remote_execution_disabled: true",
    "- arbitrary_command_disabled: true",
    "- token_printed: false",
    "- ready_for_goal_224: true"
  ) | Set-Content -Encoding UTF8 -LiteralPath $Goal223MdPath
  return $report
}

Ensure-Dirs

$output = switch ($Command) {
  "pairing-create-preview" {
    $store = Read-PairingStore
    $record = New-PairingRecord
    $idx = Find-RecordIndex @($store.records) $PairingId "pairing_id"
    if ($idx -ge 0) { $store.records[$idx] = $record } else { $store.records += $record }
    Save-PairingStore $store
    Add-Audit "pairing" "pairing_created_preview" $PairingId "Created preview pairing with hash only."
    [ordered]@{ ok = $true; pairing = $record; raw_pairing_code_returned_after_creation = $false; token_printed = $false }
  }
  "pairing-consume-preview" {
    $store = Read-PairingStore
    $idx = Find-RecordIndex @($store.records) $PairingId "pairing_id"
    if ($idx -lt 0) { throw "pairing_not_found" }
    if (@("expired", "revoked") -contains $store.records[$idx].pairing_state) { throw "pairing_not_consumable" }
    $store.records[$idx].pairing_state = "paired"
    $store.records[$idx].resident_enabled = $true
    Save-PairingStore $store
    Add-Audit "pairing" "pairing_consumed_preview" $PairingId "Consumed preview pairing without execution."
    [ordered]@{ ok = $true; pairing = $store.records[$idx]; execution_enabled = $false; token_printed = $false }
  }
  "pairing-list" { Read-PairingStore }
  "pairing-revoke-preview" {
    $store = Read-PairingStore
    $idx = Find-RecordIndex @($store.records) $PairingId "pairing_id"
    if ($idx -lt 0) { throw "pairing_not_found" }
    $now = New-Now
    $store.records[$idx].pairing_state = "revoked"
    $store.records[$idx].revoked_at = $now
    $store.revocations += [ordered]@{ schema = "skybridge.worker_pairing_revocation.v1"; pairing_id = $PairingId; worker_id = $store.records[$idx].worker_id; revoked_at = $now; pairing_state = "revoked"; execution_enabled = $false; token_printed = $false }
    Save-PairingStore $store
    Add-Audit "pairing" "pairing_revoked_preview" $PairingId "Revoked preview pairing."
    [ordered]@{ ok = $true; pairing = $store.records[$idx]; token_printed = $false }
  }
  "pairing-expire-fixture" {
    $store = Read-PairingStore
    $idx = Find-RecordIndex @($store.records) $PairingId "pairing_id"
    if ($idx -lt 0) { throw "pairing_not_found" }
    $now = New-Now
    $store.records[$idx].pairing_state = "expired"
    $store.records[$idx].expires_at = $now
    $store.expiries += [ordered]@{ schema = "skybridge.worker_pairing_expiry.v1"; pairing_id = $PairingId; worker_id = $store.records[$idx].worker_id; expires_at = $now; pairing_state = "expired"; execution_enabled = $false; token_printed = $false }
    Save-PairingStore $store
    Add-Audit "pairing" "pairing_expired_preview" $PairingId "Expired preview pairing fixture."
    [ordered]@{ ok = $true; pairing = $store.records[$idx]; token_printed = $false }
  }
  "pairing-safe-summary" { New-PairingReport (Read-PairingStore) }
  "pairing-store-report" { $report = New-PairingReport (Read-PairingStore); Write-SafeJson $report (Join-Path $ControlDir "pairing-store-report.json"); $report }
  "approval-create-preview" {
    $store = Read-ApprovalStore
    $record = New-ApprovalRecord
    $idx = Find-RecordIndex @($store.approvals) $ApprovalId "approval_id"
    if ($idx -ge 0) { $store.approvals[$idx] = $record } else { $store.approvals += $record }
    Save-ApprovalStore $store
    Add-Audit "approval" "approval_requested_preview" $ApprovalId "Requested durable preview approval."
    [ordered]@{ ok = $true; approval = $record; execution_started = $false; token_printed = $false }
  }
  "approval-approve-preview" {
    $store = Read-ApprovalStore
    $idx = Find-RecordIndex @($store.approvals) $ApprovalId "approval_id"
    if ($idx -lt 0) { throw "approval_not_found" }
    $store.approvals[$idx].state = "approved_preview"
    $store.approvals[$idx].decision_reason = "approved for preview state only; can_execute_now=false"
    Save-ApprovalStore $store
    Add-Audit "approval" "approval_approved_preview" $ApprovalId "Approved preview state without execution."
    [ordered]@{ ok = $true; approval = $store.approvals[$idx]; can_execute_now = $false; token_printed = $false }
  }
  "approval-reject-preview" {
    $store = Read-ApprovalStore
    $idx = Find-RecordIndex @($store.approvals) $ApprovalId "approval_id"
    if ($idx -lt 0) { throw "approval_not_found" }
    $store.approvals[$idx].state = "rejected"
    $store.approvals[$idx].decision_reason = "rejected preview fixture"
    Save-ApprovalStore $store
    Add-Audit "approval" "approval_rejected_preview" $ApprovalId "Rejected preview approval."
    [ordered]@{ ok = $true; approval = $store.approvals[$idx]; token_printed = $false }
  }
  "approval-expire-fixture" {
    $store = Read-ApprovalStore
    $idx = Find-RecordIndex @($store.approvals) $ApprovalId "approval_id"
    if ($idx -lt 0) { throw "approval_not_found" }
    $now = New-Now
    $store.approvals[$idx].state = "expired"
    $store.approvals[$idx].expires_at = $now
    $store.expiries += [ordered]@{ schema = "skybridge.operator_approval_expiry.v1"; approval_id = $ApprovalId; expires_at = $now; state = "expired"; can_execute_now = $false; token_printed = $false }
    Save-ApprovalStore $store
    Add-Audit "approval" "approval_expired_preview" $ApprovalId "Expired preview approval fixture."
    [ordered]@{ ok = $true; approval = $store.approvals[$idx]; token_printed = $false }
  }
  "approval-consume-preview" {
    $store = Read-ApprovalStore
    $idx = Find-RecordIndex @($store.approvals) $ApprovalId "approval_id"
    if ($idx -lt 0) { throw "approval_not_found" }
    if ($store.approvals[$idx].state -eq "consumed") { throw "approval_already_consumed" }
    $now = New-Now
    $store.approvals[$idx].state = "consumed"
    $store.approvals[$idx].consumed_at = $now
    $store.consumptions += [ordered]@{ schema = "skybridge.operator_approval_consumption.v1"; approval_id = $ApprovalId; consumed_at = $now; consumed_preview_only = $true; execution_started = $false; can_execute_now = $false; token_printed = $false }
    Save-ApprovalStore $store
    Add-Audit "approval" "approval_consumed_preview" $ApprovalId "Consumed preview approval without execution."
    [ordered]@{ ok = $true; approval = $store.approvals[$idx]; execution_started = $false; token_printed = $false }
  }
  "approval-list" { Read-ApprovalStore }
  "approval-audit-summary" { if (Test-Path -LiteralPath $ApprovalAuditPath) { Get-Content -Raw -LiteralPath $ApprovalAuditPath | ConvertFrom-Json } else { [ordered]@{ schema = "skybridge.operator_approval_audit_report.v1"; events = @(); token_printed = $false } } }
  "approval-store-report" { $report = New-ApprovalReport (Read-ApprovalStore); Write-SafeJson $report (Join-Path $ControlDir "approval-store-report.json"); $report }
  "security-rejection-fixtures" { Invoke-SecurityRejectionFixtures }
  "goal-223-report" { Write-Goal223Report }
}

if ($Json) {
  $output | ConvertTo-Json -Depth 20
} else {
  $output | ConvertTo-Json -Depth 20
}
