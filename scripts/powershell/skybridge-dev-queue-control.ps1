[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("preflight", "watch", "start-one", "start-all", "safe-pause", "stop-queue", "emergency-stop", "resume", "report", "unlock-stale-runner", "control-matrix", "control-preview", "resume-preview", "start-one-preview", "start-queue-preview", "campaign-lock-status", "campaign-lock-preview", "repo-lock-status", "repo-lock-preview", "unlock-stale-campaign-lock", "cancel-campaign-preview", "abort-campaign-preview", "hold-campaign-preview", "campaign-priority-queue", "campaign-select-next-preview", "worker-capability-matrix", "worker-readiness", "worker-route-preview", "worker-route-fixture", "worker-routing-policy", "worker-readiness-summary")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$GoalPackDir = "goals/dev-queue-189-200",
  [string]$WorkerProfile = "$HOME\.skybridge\worker.laptop-zenbookduo.json",
  [string]$HermesEnvFile = "$HOME\.skybridge\hermes.env.ps1",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$TokenEnvVar,
  [int]$MaxRuntimeMinutes = 240,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason,
  [string]$ControlAction,
  [string]$Actor = "operator",
  [string]$TargetRevision,
  [switch]$Fixture,
  [ValidateSet("Auto", "Always", "Never")]
  [string]$ColorMode = "Auto",
  [int]$PollIntervalSeconds = 5,
  [int]$RenderIntervalMilliseconds = 250,
  [switch]$SpinnerOnlyBetweenPolls,
  [int]$MaxFrames = 0,
  [switch]$Once,
  [switch]$NoClear,
  [switch]$Compact
)

$ErrorActionPreference = "Stop"

function Get-LastJsonPayloadFromOutput {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $lines = @($Text -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  for ($lineIndex = $lines.Count - 1; $lineIndex -ge 0; $lineIndex--) {
    $candidate = ([string]$lines[$lineIndex]).Trim()
    if (-not ($candidate.StartsWith("{") -or $candidate.StartsWith("["))) { continue }
    try {
      $null = $candidate | ConvertFrom-Json -ErrorAction Stop
      $prefixLines = if ($lineIndex -gt 0) { @($lines | Select-Object -First $lineIndex) } else { @() }
      return [pscustomobject]@{
        json = $candidate
        prefix = ($prefixLines -join "`n")
        suffix = ""
      }
    } catch {
    }
  }
  $starts = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $Text.Length; $i++) {
    if ($Text[$i] -eq "{" -or $Text[$i] -eq "[") { $starts.Add($i) | Out-Null }
  }
  foreach ($RequireCleanSuffix in @($true, $false)) {
    for ($s = $starts.Count - 1; $s -ge 0; $s--) {
      $start = $starts[$s]
      for ($end = $Text.Length; $end -gt $start; $end--) {
        $suffix = $Text.Substring($end)
        if ($RequireCleanSuffix -and -not [string]::IsNullOrWhiteSpace($suffix)) { continue }
        $candidate = $Text.Substring($start, $end - $start).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
          $null = $candidate | ConvertFrom-Json -ErrorAction Stop
          return [pscustomobject]@{
            json = $candidate
            prefix = $Text.Substring(0, $start)
            suffix = $suffix
          }
        } catch {
        }
      }
    }
  }
  return $null
}

function Format-ChildOutputDiagnostic {
  param([string]$Text)
  $safe = [string]$Text
  $safe = $safe -replace "(?i)(token|authorization|api[_-]?key)(\s*[:=]\s*)\S+", '$1$2[REDACTED]'
  $lines = @($safe -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -le 6) { return ($lines -join "`n") }
  return (@($lines | Select-Object -First 3) + @("...") + @($lines | Select-Object -Last 3)) -join "`n"
}

function ConvertFrom-MixedJsonOutput {
  param([object[]]$Output)
  $text = ($Output | ForEach-Object { [string]$_ }) -join "`n"
  try {
    $value = $text | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
      value = $value
      parse_mode = "whole_json"
      non_json_prefix_present = $false
      non_json_prefix = ""
      non_json_suffix = ""
    }
  } catch {
    $payload = Get-LastJsonPayloadFromOutput -Text $text
    if ($null -eq $payload) {
      $diagnostic = Format-ChildOutputDiagnostic -Text $text
      throw "Child command did not emit parseable JSON. Output excerpt:`n$diagnostic"
    }
    $value = $payload.json | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
      value = $value
      parse_mode = "extracted_json"
      non_json_prefix_present = -not [string]::IsNullOrWhiteSpace($payload.prefix)
      non_json_prefix = (Format-ChildOutputDiagnostic -Text $payload.prefix)
      non_json_suffix = (Format-ChildOutputDiagnostic -Text $payload.suffix)
    }
  }
}

function Invoke-JsonScript {
  param([string[]]$Arguments, [switch]$IncludeParseMetadata)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  if ($env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX) {
    $output = @($env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX) + @($output)
  }
  $parsed = ConvertFrom-MixedJsonOutput -Output $output
  if ($IncludeParseMetadata) { return $parsed }
  return $parsed.value
}

function Invoke-TextScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  return ($output -join "`n")
}

function Get-TokenArgs {
  $args = @()
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  return $args
}

function Get-QueueControlActionMatrix {
  $readOnly = @("refresh_status", "report", "preflight") | ForEach-Object {
    [pscustomobject]@{
      action = $_
      class = "read_only"
      allowed_modes = @("read")
      apply_allowed = $false
      reason_required = $false
      human_approval_required = $false
      requires_arm_lease = $false
      blockers = @()
      warnings = @()
      summary = "Read-only queue-control action."
      token_printed = $false
    }
  }
  $heartbeat = [pscustomobject]@{
    action = "heartbeat"
    class = "heartbeat_only"
    allowed_modes = @("apply")
    apply_allowed = $true
    reason_required = $false
    human_approval_required = $false
    requires_arm_lease = $false
    blockers = @()
    warnings = @("heartbeat_only_no_task_claim")
    summary = "Refresh worker heartbeat only."
    token_printed = $false
  }
  $safe = @("safe_pause", "stop_queue", "emergency_stop") | ForEach-Object {
    [pscustomobject]@{
      action = $_
      class = "safe_stop_pause"
      allowed_modes = @("preview", "apply")
      apply_allowed = $true
      reason_required = $true
      human_approval_required = $false
      requires_arm_lease = $false
      blockers = @()
      warnings = @("audit_required", "does_not_start_worker")
      summary = "Low-risk queue stop or pause action."
      token_printed = $false
    }
  }
  $preview = @("resume_preview", "start_one_preview", "start_queue_preview") | ForEach-Object {
    [pscustomobject]@{
      action = $_
      class = "preview"
      allowed_modes = @("preview")
      apply_allowed = $false
      reason_required = $false
      human_approval_required = $false
      requires_arm_lease = $false
      blockers = @()
      warnings = @("preview_only_no_mutation")
      summary = "Preview only; no campaign mutation or task creation."
      token_printed = $false
    }
  }
  $armed = @("start_one_apply", "start_queue_apply") | ForEach-Object {
    [pscustomobject]@{
      action = $_
      class = "armed_execution"
      allowed_modes = @()
      apply_allowed = $false
      reason_required = $true
      human_approval_required = $true
      requires_arm_lease = $true
      blockers = @("execution_apply_deferred_until_goal_197")
      warnings = @()
      summary = "Armed execution is modeled but forbidden until a later reviewed multi-worker readiness gate."
      token_printed = $false
    }
  }
  $forbidden = @("start_all", "arbitrary_shell") | ForEach-Object {
    [pscustomobject]@{
      action = $_
      class = "forbidden"
      allowed_modes = @()
      apply_allowed = $false
      reason_required = $true
      human_approval_required = $true
      requires_arm_lease = $false
      blockers = @("forbidden_action")
      warnings = @()
      summary = "Forbidden queue-control action."
      token_printed = $false
    }
  }
  @($readOnly) + @($heartbeat) + @($safe) + @($preview) + @($armed) + @($forbidden)
}

function New-LockOwner {
  [pscustomobject]@{
    owner_id = "runner-dev-queue-189-200"
    owner_kind = "campaign"
    display_name = "dev queue campaign runner"
    process_id = $null
    host = "laptop-zenbookduo"
    token_printed = $false
  }
}

function Get-CampaignLockFixture {
  param([switch]$Stale)
  [pscustomobject]@{
    schema = "skybridge.campaign_lock.v1"
    lock_id = $(if ($Stale) { "campaign_lock_dev_queue_189_200_stale" } else { "campaign_lock_dev_queue_189_200" })
    campaign_id = $CampaignId
    project_id = $ProjectId
    lock_owner = New-LockOwner
    heartbeat_at = $(if ($Stale) { "2026-06-07T22:00:00.000Z" } else { "2026-06-08T00:00:00.000Z" })
    expires_at = $(if ($Stale) { "2026-06-07T22:30:00.000Z" } else { "2026-06-08T00:30:00.000Z" })
    lock_status = $(if ($Stale) { "stale" } else { "held" })
    release_reason = $null
    operator_reason = $(if ($Stale) { $null } else { "Goal 196 fixture: campaign held for lock review." })
    age_seconds = $(if ($Stale) { 7200 } else { 0 })
    stale = [bool]$Stale
    token_printed = $false
  }
}

function Get-RepoLockFixture {
  param([switch]$Stale, [switch]$UnknownOwner)
  $owner = New-LockOwner
  if ($UnknownOwner) {
    $owner.owner_id = "unknown"
    $owner.owner_kind = "unknown"
    $owner.display_name = "unknown lock owner"
  }
  [pscustomobject]@{
    schema = "skybridge.repo_exclusive_lock.v1"
    lock_id = $(if ($Stale) { "repo_lock_skybridge_agent_hub_stale" } else { "repo_lock_skybridge_agent_hub" })
    campaign_id = $CampaignId
    project_id = $ProjectId
    repo_id = "skybridge-agent-hub"
    worktree_identity = "V:/src/skybridge-agent-hub"
    lock_owner = $owner
    heartbeat_at = $(if ($Stale) { "2026-06-07T22:00:00.000Z" } else { "2026-06-08T00:00:00.000Z" })
    expires_at = $(if ($Stale) { "2026-06-07T22:30:00.000Z" } else { "2026-06-08T00:30:00.000Z" })
    lock_status = $(if ($Stale) { "stale" } else { "active" })
    release_reason = $null
    operator_reason = $null
    age_seconds = $(if ($Stale) { 7200 } else { 0 })
    stale = [bool]$Stale
    blocks_execution_preview = $true
    force_release_allowed = $false
    token_printed = $false
  }
}

function Get-CampaignPriorityQueueFixture {
  [pscustomobject]@{
    schema = "skybridge.campaign_priority_queue.v1"
    project_id = $ProjectId
    active_campaign_id = $CampaignId
    current_campaign_id = $CampaignId
    one_active_campaign_per_project = $true
    deterministic_order = $true
    filter_statuses = @("ready", "paused", "held", "completed", "archived")
    items = @(
      [pscustomobject]@{ campaign_id = $CampaignId; project_id = $ProjectId; priority = 10; status = "ready"; current_goal_id = "super-196-campaign-locking-multi-campaign-queue"; current_step_id = "$CampaignId`:super-196-campaign-locking-multi-campaign-queue"; blocked_reason = "repo_lock_requires_review_before_execution_preview"; selected = $true; token_printed = $false },
      [pscustomobject]@{ campaign_id = "bootstrap-mvp"; project_id = $ProjectId; priority = 20; status = "held"; current_goal_id = "super-184b-operator-console-dashboard"; current_step_id = "bootstrap-mvp:super-184b-operator-console-dashboard"; blocked_reason = "lower_priority_campaign_held_while_dev_queue_is_current"; selected = $false; token_printed = $false }
    )
    selection = [pscustomobject]@{
      selected_campaign_id = $CampaignId
      decision = "blocked"
      blocked_campaign_reason = "active_repo_lock_blocks_execution_preview"
      queue_decision_summary = "$CampaignId is highest priority, but repo lock review blocks start previews."
      execution_side_effects = $false
      token_printed = $false
    }
    token_printed = $false
  }
}

function New-LockAuditEvent {
  param([string]$Action, [string]$ReasonText, [object]$Lock)
  [pscustomobject]@{
    schema = "skybridge.lock_audit_event.v1"
    audit_event_id = "audit_lock_$([Guid]::NewGuid().ToString("n").Substring(0, 12))"
    action = $Action
    source = "cli_fixture"
    actor = $Actor
    campaign_id = $CampaignId
    project_id = $ProjectId
    lock_id = if ($Lock) { $Lock.lock_id } else { $null }
    lock_status = if ($Lock) { $Lock.lock_status } else { $null }
    reason = $ReasonText
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    raw_logs_included = $false
    token_printed = $false
  }
}

function Write-LockAuditEvent {
  param($AuditEvent)
  $auditDir = Join-Path (Join-Path ".agent" "tmp") "campaign-lock-audit"
  New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
  $auditPath = Join-Path $auditDir "$CampaignId.jsonl"
  ($AuditEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $auditPath -Encoding UTF8
  return $auditPath
}

function Invoke-LockDecision {
  param(
    [string]$Action,
    [string]$DecisionMode,
    [object]$Lock,
    [switch]$RequiresStale,
    [switch]$RefuseActive
  )
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  if ($DecisionMode -eq "apply" -and [string]::IsNullOrWhiteSpace($Reason)) { $blockers.Add("reason_required") | Out-Null }
  if ($RequiresStale -and $Lock -and -not [bool]$Lock.stale) { $blockers.Add("lock_not_stale") | Out-Null }
  if ($RefuseActive -and $Lock -and [string]$Lock.lock_status -eq "active" -and -not [bool]$Lock.stale) { $blockers.Add("active_lock_force_release_refused") | Out-Null }
  if ($DecisionMode -eq "dry-run") { $warnings.Add("preview_only_no_mutation") | Out-Null }
  $allowed = ($blockers.Count -eq 0)
  $audit = $null
  $auditPath = $null
  if ($allowed -and $DecisionMode -eq "apply") {
    $audit = New-LockAuditEvent -Action $Action -ReasonText $Reason -Lock $Lock
    $auditPath = Write-LockAuditEvent -AuditEvent $audit
  }
  [pscustomobject]@{
    schema = "skybridge.lock_recovery_decision.v1"
    ok = $allowed
    command = $Command
    action = $Action
    mode = $DecisionMode
    allowed = $allowed
    lock_status = if ($Lock) { $Lock.lock_status } else { $null }
    requires_reason = $true
    reason_recorded = (-not [string]::IsNullOrWhiteSpace($Reason))
    blockers = @($blockers)
    warnings = @($warnings)
    lock = $Lock
    audit_event_id = if ($audit) { $audit.audit_event_id } else { $null }
    audit_path = $auditPath
    task_created = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    token_printed = $false
  }
}

function Get-QueueControlState {
  $matrix = Get-QueueControlActionMatrix
  [pscustomobject]@{
    schema = "skybridge.queue_control_state.v1"
    project_id = $ProjectId
    campaign_id = $CampaignId
    current_step_id = "$CampaignId`:super-196-campaign-locking-multi-campaign-queue"
    current_goal_id = "super-196-campaign-locking-multi-campaign-queue"
    worker_status = "offline"
    active_tasks = 0
    stale_leases = 0
    can_start_one = $false
    can_start_queue = $false
    can_resume = $false
    state_hash = "fixture-goal-196-locking-offline-active0-stale0-repolock"
    revision = "fixture-goal-196-revision"
    action_matrix = @($matrix)
    blockers = @("worker_service_offline", "active_repo_lock_blocks_execution_preview", "execution_apply_disabled_until_goal_197")
    warnings = @("manual_goal_pack_review_required", "multiple_campaigns_require_selection_review")
    campaign_lock = Get-CampaignLockFixture
    repo_exclusive_lock = Get-RepoLockFixture
    priority_queue = Get-CampaignPriorityQueueFixture
    arm_lease = [pscustomobject]@{
      lease_id = "lease_fixture_goal_194_preview_only"
      campaign_id = $CampaignId
      allowed_actions = @("resume_preview", "start_one_preview", "start_queue_preview")
      expires_at = "2026-06-08T00:30:00.000Z"
      created_by = "fixture"
      reason = "schema fixture only; not valid for apply execution"
      consumed_at = $null
      token_printed = $false
    }
    token_printed = $false
  }
}

function New-QueueControlAuditEvent {
  param([string]$Action, [string]$Mode, [string]$ReasonText, [string[]]$Blockers, [string[]]$Warnings, [string]$Revision)
  [pscustomobject]@{
    schema = "skybridge.queue_control_audit_event.v1"
    audit_event_id = "audit_queue_control_$([Guid]::NewGuid().ToString("n").Substring(0, 12))"
    action = $Action
    source = "cli"
    mode = $Mode
    actor = $Actor
    campaign_id = $CampaignId
    current_step_id = "$CampaignId`:super-196-campaign-locking-multi-campaign-queue"
    target_revision = $Revision
    reason = $ReasonText
    blockers = @($Blockers)
    warnings = @($Warnings)
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    token_printed = $false
  }
}

function Write-QueueControlAuditEvent {
  param($AuditEvent)
  $auditDir = Join-Path (Join-Path ".agent" "tmp") "queue-control-audit"
  New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
  $auditPath = Join-Path $auditDir "$CampaignId.jsonl"
  ($AuditEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $auditPath -Encoding UTF8
  return $auditPath
}

function Invoke-QueueControlContract {
  param(
    [string]$Action,
    [ValidateSet("read", "preview", "apply")]
    [string]$ControlMode,
    [switch]$CreateAudit
  )
  $state = Get-QueueControlState
  $entry = @($state.action_matrix | Where-Object { $_.action -eq $Action } | Select-Object -First 1)
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  if ($entry) {
    foreach ($item in @($entry.blockers)) {
      if (-not [string]::IsNullOrWhiteSpace([string]$item)) { $blockers.Add([string]$item) | Out-Null }
    }
    foreach ($item in @($entry.warnings)) {
      if (-not [string]::IsNullOrWhiteSpace([string]$item)) { $warnings.Add([string]$item) | Out-Null }
    }
  } else {
    $blockers.Add("unknown_action") | Out-Null
  }
  $revision = if ([string]::IsNullOrWhiteSpace($TargetRevision)) { $state.state_hash } else { $TargetRevision }
  if ([string]::IsNullOrWhiteSpace($TargetRevision) -and $Command -eq "control-preview") {
    $blockers.Add("target_revision_required") | Out-Null
  } elseif ($revision -ne $state.state_hash) {
    $blockers.Add("target_revision_mismatch") | Out-Null
  }
  if ($entry -and @($entry.allowed_modes) -notcontains $ControlMode) { $blockers.Add("mode_not_allowed") | Out-Null }
  if ($ControlMode -eq "apply" -and $entry -and -not [bool]$entry.apply_allowed) { $blockers.Add("apply_forbidden_in_goal_196") | Out-Null }
  if ($ControlMode -eq "apply" -and $entry -and [bool]$entry.reason_required -and [string]::IsNullOrWhiteSpace($Reason)) { $blockers.Add("reason_required") | Out-Null }
  if ($Action -in @("start_one_apply", "start_queue_apply", "start_all", "arbitrary_shell")) {
    $blockers.Add("no_execution_enablement_in_goal_196") | Out-Null
  }
  if ($Action -in @("start_one_preview", "start_queue_preview", "start_one_apply", "start_queue_apply")) {
    $blockers.Add("active_repo_lock_blocks_execution_preview") | Out-Null
  }
  $allowed = ($blockers.Count -eq 0)
  $audit = $null
  $auditPath = $null
  if ($CreateAudit -and $allowed) {
    $audit = New-QueueControlAuditEvent -Action $Action -Mode $ControlMode -ReasonText $Reason -Blockers @($blockers) -Warnings @($warnings) -Revision $revision
    $auditPath = Write-QueueControlAuditEvent -AuditEvent $audit
  }
  [pscustomobject]@{
    schema = "skybridge.queue_control_action_response.v1"
    ok = $allowed
    command = $Command
    mode = $ControlMode
    action = $Action
    allowed = $allowed
    blockers = @($blockers)
    warnings = @($warnings)
    audit_event_id = if ($audit) { $audit.audit_event_id } else { $null }
    audit_path = $auditPath
    state = $state
    state_hash = $state.state_hash
    target_revision = $revision
    reason_required = if ($entry) { [bool]$entry.reason_required } else { $true }
    human_approval_required = if ($entry) { [bool]$entry.human_approval_required } else { $true }
    mutates = ($ControlMode -eq "apply" -and $allowed)
    task_created = $false
    worker_loop_started = $false
    token_printed = $false
    summary = "queue control $Action $ControlMode allowed=$allowed"
  }
}

function Test-GitPreflight {
  $branch = (git branch --show-current).Trim()
  $dirty = -not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim())
  $mainSync = "unknown"
  try {
    git fetch --quiet origin main *> $null
    $mainSync = ((git rev-parse main).Trim() -eq (git rev-parse origin/main).Trim())
  } catch {
    $mainSync = "unknown"
  }
  [pscustomobject]@{ branch = $branch; dirty = $dirty; main_sync = $mainSync }
}

function Write-ControlOutput {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 80 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $ProjectId"
  "Campaign:     $CampaignId"
  "OK:           $($Result.ok)"
  if ($Result.summary) { $Result.summary }
  if ($Result.instructions) { $Result.instructions }
}

function Invoke-Preflight {
  $tokenArgs = Get-TokenArgs
  $git = Test-GitPreflight
  $active = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-ActiveOnly", "-Json", "-ColorMode", "Never"))
  $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
  $campaign = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $runner = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $worker = $null
  if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
    $worker = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-Json")
  }
  $goal189 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
  $goal190 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-190-campaign-run-report-evidence-ledger" })[0]
  $goal191 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-191-readonly-operator-dashboard" })[0]
  $goal192 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-192-dashboard-safe-actions" })[0]
  $goal193 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-193-notification-attention-loop" })[0]
  $goal194 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-194-worker-service-mode" })[0]
  $goal189Recovered = $false
  if ($goal189 -and $goal189.evidence_summary) {
    $goal189Recovered = [bool]$goal189.evidence_summary.recovered -or [string]$goal189.evidence_summary.recovery_status -in @("recovered", "completed")
  }
  $goal190LinkedTaskCount = if ($goal190) { @($goal190.linked_task_ids).Count } else { 0 }
  $goal190LinkedPrCount = if ($goal190) { @($goal190.linked_pr_urls).Count } else { 0 }
  $goal190Unexecuted = ($goal190 -and $goal190LinkedTaskCount -eq 0 -and $goal190LinkedPrCount -eq 0)
  $goal192Unexecuted = ($goal192 -and @($goal192.linked_task_ids).Count -eq 0 -and @($goal192.linked_pr_urls).Count -eq 0)
  $goal194Unexecuted = ($goal194 -and @($goal194.linked_task_ids).Count -eq 0 -and @($goal194.linked_pr_urls).Count -eq 0)
  $checks = [ordered]@{
    git_clean = -not [bool]$git.dirty
    active_tasks_zero = ([int]$active.task_summary.active -eq 0)
    stale_leases_zero = ([int]$hygiene.task_summary.stale_leases -eq 0)
    runner_lock_clear = ([string]$runner.runner_lock_status -in @("none", "released"))
    campaign_exists = ($null -ne $campaign.campaign)
    goal_189_completed = ($goal189 -and [string]$goal189.status -eq "completed")
    goal_189_recovered_or_evidence_complete = ($goal189 -and $goal189Recovered)
    goal_190_completed = ($goal190 -and [string]$goal190.status -eq "completed")
    goal_191_completed = ($goal191 -and [string]$goal191.status -eq "completed")
    goal_192_completed = ($goal192 -and [string]$goal192.status -eq "completed")
    goal_193_completed = ($goal193 -and [string]$goal193.status -eq "completed")
    goal_194_current = ($goal194 -and [string]$campaign.campaign.current_step_id -eq [string]$goal194.campaign_step_id)
    goal_194_ready = ($goal194 -and [string]$goal194.status -eq "ready")
    goal_194_unexecuted = $goal194Unexecuted
    goal_190_unexecuted = $goal190Unexecuted
    project_paused = ([string]$active.control.state -eq "paused")
  }
  [pscustomobject]@{
    ok = -not (@($checks.GetEnumerator() | Where-Object { -not $_.Value }).Count -gt 0)
    command = "preflight"
    mode = "read"
    token_printed = $false
    git = $git
    checks = $checks
    active_tasks = [int]$active.task_summary.active
    stale_leases = [int]$hygiene.task_summary.stale_leases
    runner_lock_status = [string]$runner.runner_lock_status
    campaign_status = [string]$campaign.campaign.status
    current_step = [string]$campaign.campaign.current_step_id
    previous_step = if ($goal189) { [pscustomobject]@{ goal_id = [string]$goal189.goal_id; status = [string]$goal189.status; linked_task_ids = @($goal189.linked_task_ids); linked_pr_urls = @($goal189.linked_pr_urls); recovered = $goal189Recovered } } else { $null }
    goal_190_detail = if ($goal190) { [pscustomobject]@{ goal_id = [string]$goal190.goal_id; status = [string]$goal190.status; linked_task_ids = @($goal190.linked_task_ids); linked_pr_urls = @($goal190.linked_pr_urls); unexecuted = $goal190Unexecuted } } else { $null }
    current_step_detail = if ($goal194) { [pscustomobject]@{ goal_id = [string]$goal194.goal_id; status = [string]$goal194.status; linked_task_ids = @($goal194.linked_task_ids); linked_pr_urls = @($goal194.linked_pr_urls); unexecuted = $goal194Unexecuted } } else { $null }
    worker_status = if ($worker) { [string]$worker.remote_status } else { "unknown" }
    worker_current_task_id = if ($worker) { $worker.current_task_id } else { $null }
    next_safe_action = "Goal 196 lock review only: inspect campaign/repo locks and priority queue; start-one/start-queue apply remain disabled."
    summary = "preflight active=$($active.task_summary.active) stale_leases=$($hygiene.task_summary.stale_leases) runner_lock=$($runner.runner_lock_status) current=$($campaign.campaign.current_step_id) goal194_unexecuted=$goal194Unexecuted"
  }
}

if ($Apply -and $DryRun) { throw "Use either -Apply or -DryRun, not both." }
$mode = if ($Apply) { "apply" } else { "dry-run" }
$tokenArgs = Get-TokenArgs
$result = $null

switch ($Command) {
  "control-matrix" {
    $state = Get-QueueControlState
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "read"
      schema = "skybridge.queue_control_action_matrix.v1"
      campaign_id = $CampaignId
      action_matrix = @($state.action_matrix)
      state_hash = $state.state_hash
      token_printed = $false
    }
  }
  "control-preview" {
    $action = if ([string]::IsNullOrWhiteSpace($ControlAction)) { "start_one_preview" } else { $ControlAction }
    $result = Invoke-QueueControlContract -Action $action -ControlMode "preview"
  }
  "resume-preview" {
    $result = Invoke-QueueControlContract -Action "resume_preview" -ControlMode "preview"
  }
  "start-one-preview" {
    $result = Invoke-QueueControlContract -Action "start_one_preview" -ControlMode "preview"
  }
  "start-queue-preview" {
    $result = Invoke-QueueControlContract -Action "start_queue_preview" -ControlMode "preview"
  }
  "campaign-lock-status" {
    $lock = Get-CampaignLockFixture
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; campaign_lock = $lock; token_printed = $false }
  }
  "campaign-lock-preview" {
    $lock = Get-CampaignLockFixture -Stale
    $result = Invoke-LockDecision -Action "campaign_lock_preview" -DecisionMode "dry-run" -Lock $lock
  }
  "repo-lock-status" {
    $lock = Get-RepoLockFixture
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; repo_exclusive_lock = $lock; token_printed = $false }
  }
  "repo-lock-preview" {
    $lock = Get-RepoLockFixture
    $result = Invoke-LockDecision -Action "repo_lock_preview" -DecisionMode "dry-run" -Lock $lock -RefuseActive
  }
  "unlock-stale-campaign-lock" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "unlock-stale-campaign-lock requires -Reason." }
    $lock = Get-CampaignLockFixture -Stale
    $result = Invoke-LockDecision -Action "unlock_stale_campaign_lock" -DecisionMode $(if ($Apply) { "apply" } else { "dry-run" }) -Lock $lock -RequiresStale
    if ($result.allowed -and $Apply) {
      $result.lock.lock_status = "released"
      $result.lock.release_reason = "stale_unlock"
      $result.lock.operator_reason = $Reason
      $result.lock.stale = $false
    }
  }
  "cancel-campaign-preview" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "cancel-campaign-preview requires -Reason." }
    $result = Invoke-LockDecision -Action "cancel_campaign" -DecisionMode $(if ($Apply) { "apply" } else { "dry-run" }) -Lock (Get-CampaignLockFixture)
    $result | Add-Member -NotePropertyName campaign_status_after -NotePropertyValue $(if ($result.allowed -and $Apply) { "cancelled" } else { "ready" }) -Force
  }
  "abort-campaign-preview" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "abort-campaign-preview requires -Reason." }
    $result = Invoke-LockDecision -Action "abort_campaign" -DecisionMode $(if ($Apply) { "apply" } else { "dry-run" }) -Lock (Get-CampaignLockFixture)
    $result | Add-Member -NotePropertyName campaign_status_after -NotePropertyValue $(if ($result.allowed -and $Apply) { "aborted" } else { "ready" }) -Force
    $result | Add-Member -NotePropertyName process_killed -NotePropertyValue $false -Force
  }
  "hold-campaign-preview" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "hold-campaign-preview requires -Reason." }
    $result = Invoke-LockDecision -Action "hold_campaign" -DecisionMode $(if ($Apply) { "apply" } else { "dry-run" }) -Lock (Get-CampaignLockFixture)
    $result | Add-Member -NotePropertyName campaign_status_after -NotePropertyValue $(if ($result.allowed -and $Apply) { "held" } else { "ready" }) -Force
  }
  "campaign-priority-queue" {
    $queue = Get-CampaignPriorityQueueFixture
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; priority_queue = $queue; token_printed = $false }
  }
  "campaign-select-next-preview" {
    $queue = Get-CampaignPriorityQueueFixture
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "dry-run"
      schema = "skybridge.campaign_select_next_preview.v1"
      selection = $queue.selection
      selected_campaign_id = $queue.selection.selected_campaign_id
      blocked_campaign_reason = $queue.selection.blocked_campaign_reason
      task_created = $false
      worker_loop_started = $false
      queue_execution_enabled = $false
      token_printed = $false
    }
  }
  { $_ -in @("worker-capability-matrix", "worker-readiness", "worker-route-preview", "worker-route-fixture", "worker-routing-policy", "worker-readiness-summary") } {
    $workerArgs = @("-File", ".\scripts\powershell\skybridge-worker-routing.ps1", "-Command", $Command, "-ProjectId", $ProjectId, "-Json")
    $result = Invoke-JsonScript $workerArgs
  }
  "preflight" {
    if ($Fixture) { $result = Invoke-QueueControlContract -Action "preflight" -ControlMode "read" }
    else { $result = Invoke-Preflight }
  }
  "watch" {
    $watchArgs = @("-File", ".\scripts\powershell\skybridge-campaign-watch.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-CampaignId", $CampaignId, "-ColorMode", $ColorMode) + $tokenArgs
    if ($Once) { $watchArgs += "-Once" }
    if ($NoClear) { $watchArgs += "-NoClear" }
    if ($Compact) { $watchArgs += "-Compact" }
    if ($PollIntervalSeconds -gt 0) { $watchArgs += @("-PollIntervalSeconds", [string]$PollIntervalSeconds) }
    if ($RenderIntervalMilliseconds -gt 0) { $watchArgs += @("-RenderIntervalMilliseconds", [string]$RenderIntervalMilliseconds) }
    if ($SpinnerOnlyBetweenPolls) { $watchArgs += "-SpinnerOnlyBetweenPolls" }
    if ($MaxFrames -gt 0) { $watchArgs += @("-MaxFrames", [string]$MaxFrames) }
    if ($Json) { $watchArgs += "-Json" }
    if ($OutputFile) { $watchArgs += @("-OutputFile", $OutputFile) }
    if ($Json) { $result = Invoke-JsonScript $watchArgs } else { Invoke-TextScript $watchArgs; return }
  }
  "start-one" {
    if ($Apply) {
      $result = Invoke-QueueControlContract -Action "start_one_apply" -ControlMode "apply"
      break
    }
    if ($DryRun -or $Fixture -or -not $Apply) {
      $result = Invoke-QueueControlContract -Action "start_one_preview" -ControlMode "preview"
      break
    }
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "1", "-MaxTasks", "1", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $child = Invoke-JsonScript $args -IncludeParseMetadata
    $result = $child.value
    $result | Add-Member -NotePropertyName child_non_json_prefix_present -NotePropertyValue ([bool]$child.non_json_prefix_present) -Force
    $result | Add-Member -NotePropertyName child_parse_mode -NotePropertyValue ([string]$child.parse_mode) -Force
    if ($child.non_json_prefix_present) { $result | Add-Member -NotePropertyName child_non_json_prefix -NotePropertyValue ([string]$child.non_json_prefix) -Force }
    if (-not $result.PSObject.Properties["task_created"]) {
      $taskId = $null
      if ($result.final_status -and $result.final_status.campaign -and $result.final_status.campaign.steps) {
        $current = @($result.final_status.campaign.steps | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
        if ($current -and @($current.linked_task_ids).Count -gt 0) { $taskId = [string]@($current.linked_task_ids)[0] }
      }
      $result | Add-Member -NotePropertyName task_created -NotePropertyValue (-not [string]::IsNullOrWhiteSpace($taskId)) -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $taskId -Force
      $result | Add-Member -NotePropertyName task_created_summary -NotePropertyValue $(if ($taskId) { "task created: $taskId" } else { "no task created" }) -Force
    }
    if ([string]$result.runner_status -eq "held" -and [string]$result.stop_reason -eq "max_steps_reached") {
      $result.ok = $true
      $result | Add-Member -NotePropertyName bounded_completion -NotePropertyValue $true -Force
    }
  }
  "start-all" {
    $result = Invoke-QueueControlContract -Action "start_all" -ControlMode $(if ($Apply) { "apply" } else { "preview" })
    break
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $child = Invoke-JsonScript $args -IncludeParseMetadata
    $result = $child.value
    $result | Add-Member -NotePropertyName child_non_json_prefix_present -NotePropertyValue ([bool]$child.non_json_prefix_present) -Force
    $result | Add-Member -NotePropertyName child_parse_mode -NotePropertyValue ([string]$child.parse_mode) -Force
    if ($child.non_json_prefix_present) { $result | Add-Member -NotePropertyName child_non_json_prefix -NotePropertyValue ([string]$child.non_json_prefix) -Force }
    if (-not $result.PSObject.Properties["task_created"]) {
      $result | Add-Member -NotePropertyName task_created -NotePropertyValue $false -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $null -Force
      $result | Add-Member -NotePropertyName task_created_summary -NotePropertyValue "no task id surfaced by child command" -Force
    }
    if ([string]$result.runner_status -eq "held" -and [string]$result.stop_reason -eq "max_steps_reached") {
      $result.ok = $true
      $result | Add-Member -NotePropertyName bounded_completion -NotePropertyValue $true -Force
    }
  }
  "safe-pause" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "safe-pause requires -Reason." }
    if ($Fixture -or -not $Apply) {
      $result = Invoke-QueueControlContract -Action "safe_pause" -ControlMode $(if ($Apply) { "apply" } else { "preview" }) -CreateAudit:$Apply
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $hold = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-hold", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Apply", "-Json"))
      $contract = Invoke-QueueControlContract -Action "safe_pause" -ControlMode "apply" -CreateAudit
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; runner = $hold; stop_requested = [bool]$control.control.stop_requested; reason = $Reason; audit_event_id = $contract.audit_event_id; summary = "safe-pause applied: project paused and stop_requested=false." }
    }
  }
  "stop-queue" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "stop-queue requires -Reason." }
    $result = Invoke-QueueControlContract -Action "stop_queue" -ControlMode $(if ($Apply) { "apply" } else { "preview" }) -CreateAudit:$Apply
  }
  "emergency-stop" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "emergency-stop requires -Reason." }
    if ($Fixture -or -not $Apply) {
      $result = Invoke-QueueControlContract -Action "emergency_stop" -ControlMode $(if ($Apply) { "apply" } else { "preview" }) -CreateAudit:$Apply
      $result | Add-Member -NotePropertyName instructions -NotePropertyValue "Dry-run/fixture path. With real -Apply, press Ctrl+C in any runner window if it is still running." -Force
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "stop", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $contract = Invoke-QueueControlContract -Action "emergency_stop" -ControlMode "apply" -CreateAudit
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; stop_requested = [bool]$control.control.stop_requested; task_created = $false; worker_loop_started = $false; reason = $Reason; audit_event_id = $contract.audit_event_id; instructions = "Press Ctrl+C in the runner window if it is still running."; summary = "emergency-stop applied: stop_requested=true; no task was created." }
    }
  }
  "resume" {
    if ($Apply) {
      $result = Invoke-QueueControlContract -Action "resume_preview" -ControlMode "apply"
      break
    }
    if ($Fixture) {
      $result = Invoke-QueueControlContract -Action "resume_preview" -ControlMode "preview"
      break
    }
    $preflight = Invoke-Preflight
    if (-not $Apply) {
      $stopRequested = $false
      try {
        $controlState = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "status", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
        $stopRequested = [bool]$controlState.control.stop_requested
      } catch {
        $controlState = $null
      }
      $goal190Unexecuted = $false
      if ($preflight.current_step_detail) { $goal190Unexecuted = [bool]$preflight.current_step_detail.unexecuted }
      $result = [pscustomobject]@{
        ok = $true
        command = $Command
        mode = "dry-run"
        token_printed = $false
        mutates = $false
        would_clear_stop_requested = $true
        stop_requested_current = $stopRequested
        required_recovery_action = if ($stopRequested) { "Run safe-pause -Apply first to restore paused stop_requested=false, then rerun resume dry-run." } else { $null }
        would_refresh_worker_heartbeat = (Test-Path -LiteralPath $WorkerProfile -PathType Leaf)
        would_resume_runner = $true
        would_execute_goal_190 = $false
        current_step = [string]$preflight.current_step
        goal_190_unexecuted = $goal190Unexecuted
        preflight = $preflight
        next_safe_action = "Do not execute Goal 190 from Goal 188G. Run the Pre-190 Acceptance Gate, then use start-one only after explicit operator approval."
        summary = "resume dry-run: no mutation; current step is $($preflight.current_step); Goal 190 execution is blocked in this goal."
      }
    } else {
      Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json")) | Out-Null
      if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
        Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "register-heartbeat", "-ConfigFile", $WorkerProfile, "-Json") | Out-Null
      }
      $result = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "resume", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-MaxSteps", "12", "-MaxTasks", "12", "-StopOnFailure", "-AllowAutoMerge", "-AllowEvidenceRepair", "-HumanApproved", "-HumanApprovalReason", "Operator resumed bounded dev queue execution.", "-Apply", "-Json") + $tokenArgs)
    }
  }
  "report" {
    $report = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-report", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; token_printed = $false; report = $report.report; hygiene_summary = $hygiene.hygiene_summary; active_tasks = $hygiene.task_summary.active; stale_leases = $hygiene.task_summary.stale_leases }
  }
  "unlock-stale-runner" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "unlock-stale-runner requires -Reason." }
    $status = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    if ([string]$status.runner_lock_status -eq "active") { throw "Refusing to unlock active non-stale runner lock." }
    if ([string]$status.runner_lock_status -notin @("stale", "released", "none")) { throw "Unsupported runner lock status: $($status.runner_lock_status)" }
    if ([string]$status.runner_lock_status -in @("released", "none")) {
      $result = [pscustomobject]@{
        ok = $true
        command = $Command
        mode = if ($Apply) { "apply" } else { "dry-run" }
        token_printed = $false
        runner_lock_status = [string]$status.runner_lock_status
        lock = $status.runner_lock
        would_unlock = $false
        unlocked = $false
        requires_apply = (-not $Apply)
        reason = $Reason
        summary = "No stale runner lock is present; unlock is a no-op."
      }
      break
    }
    $unlockArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-unlock", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Json")
    if ($Apply) { $unlockArgs += "-Apply" } else { $unlockArgs += "-DryRun" }
    $result = Invoke-JsonScript $unlockArgs
    $result | Add-Member -NotePropertyName command -NotePropertyValue $Command -Force
    $result | Add-Member -NotePropertyName mode -NotePropertyValue $(if ($Apply) { "apply" } else { "dry-run" }) -Force
    $result | Add-Member -NotePropertyName requires_apply -NotePropertyValue (-not $Apply) -Force
    $result | Add-Member -NotePropertyName reason -NotePropertyValue $Reason -Force
  }
}

if (-not $result.PSObject.Properties["command"]) {
  $result | Add-Member -NotePropertyName command -NotePropertyValue $Command
}
if (-not $result.PSObject.Properties["mode"]) {
  $result | Add-Member -NotePropertyName mode -NotePropertyValue $mode
}
if (-not $result.PSObject.Properties["token_printed"]) {
  $result | Add-Member -NotePropertyName token_printed -NotePropertyValue $false
}
Write-ControlOutput $result
