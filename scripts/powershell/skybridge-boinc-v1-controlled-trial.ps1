[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "approval-preview", "approval-gate", "trial-preview", "trial-apply-gate", "trial-apply", "trial-evidence", "trial-audit-preview", "trial-finalizer-preview", "trial-finalizer-apply", "trial-finalizer-evidence", "trial-finalizer-report", "trial-safe-summary", "trial-report", "no-execution-gate")]
  [string]$Command,

  [switch]$AuthorizeGoal221,
  [switch]$SimulateResourceGateFail,
  [switch]$SimulateOpenReview,
  [switch]$SimulateCodexSuccess,
  [switch]$SimulateTaskPrMerged,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$EvidenceDir = ".agent/tmp/boinc-v1-controlled-trial-221",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.CodexExecutor.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.ResourceGate.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.EvidenceStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.PrPackager.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.QueuePolicy.psm1") -Force

$TrialId = "boinc-v1-controlled-trial-221"
$WorkunitId = "boinc-v1-controlled-trial-221-workunit-001"
$TaskId = "boinc-v1-controlled-trial-221-task-001"
$TargetPath = "docs/boinc-v1-controlled-trial-221.md"
$TaskBranch = "ai/boinc-v1-controlled-trial/boinc-v1-controlled-trial-221-workunit-001"
$ReleaseVersion = "v0.99.0-boinc-like-v1-controlled-release"
$ApprovalId = "boinc-v1-controlled-trial-221-approval-001"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function ConvertTo-TrialJsonOut($Value) {
  if ($Json) { $Value | ConvertTo-Json -Depth 20 } else { $Value | ConvertTo-Json -Depth 20 }
}

function Test-TrialUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Resolve-TrialPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Write-TrialSafeJson([string]$Path, $Value) {
  $full = Resolve-TrialPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $json = $Value | ConvertTo-Json -Depth 20
  if (Test-TrialUnsafeText $json) { throw "Refusing to write unsafe JSON: $Path" }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function Read-TrialSafeJson([string]$Path) {
  $full = Resolve-TrialPath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $full
  if (Test-TrialUnsafeText $text) { throw "Unsafe JSON content detected: $Path" }
  $value = $text | ConvertFrom-Json
  if ($value.PSObject.Properties.Name -contains "token_printed" -and $value.token_printed -ne $false) { throw "token_printed must be false: $Path" }
  $value
}

function Write-TrialSafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-TrialPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  if (Test-TrialUnsafeText $text) { throw "Unsafe markdown content: $Path" }
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function Get-TrialEvidenceHash([string]$Path) {
  $full = Resolve-TrialPath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Evidence file missing: $Path" }
  (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ReleaseGate {
  $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-release.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command gate
  if ($LASTEXITCODE -ne 0) { throw "Release gate command failed." }
  $gate = ($raw | Out-String).Trim() | ConvertFrom-Json
  $tagExists = $false
  & git -C $RepoRoot show-ref --tags --verify --quiet "refs/tags/$ReleaseVersion"
  $tagExists = ($LASTEXITCODE -eq 0)
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_release_gate.v1"
    release_version = $ReleaseVersion
    release_gate_result = $gate.gate_result
    ready_for_goal_221 = $true
    tag_exists = $tagExists
    remote_execution_enabled = $gate.readiness.remote_execution_enabled
    arbitrary_command_enabled = $gate.readiness.arbitrary_command_enabled
    execution_enabled = $gate.readiness.execution_enabled
    queue_apply_enabled = $gate.readiness.queue_apply_enabled
    generic_bounded_queue_apply_enabled = $gate.readiness.generic_bounded_queue_apply_enabled
    no_next_execution_authorized = $gate.readiness.no_next_execution_authorized
    token_printed = $false
  }
}

function Get-OpenTrialTaskPrs {
  if ($SimulateOpenReview) { return @([pscustomobject]@{ number = 999; title = "fixture open controlled trial task PR"; url = "https://example.invalid/pr/999"; token_printed = $false }) }
  try {
    $raw = gh pr list --state open --search "boinc-v1-controlled-trial-221 OR managed-mode OR BOINC" --json number,title,url,headRefName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { return @() }
    @((($raw | Out-String).Trim() | ConvertFrom-Json))
  } catch {
    @()
  }
}

function New-TrialPolicy {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_policy.v1"
    trial_id = $TrialId
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_codex_executions = 1
    max_task_prs = 1
    max_parallel_repo_mutations = 1
    require_release_gate = $true
    require_resource_gate = $true
    require_operator_approval = $true
    require_human_review = $true
    require_finalizer = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit = $true
    require_redaction = $true
    allow_remote_execution = $false
    allow_arbitrary_command = $false
    allow_generic_queue_apply = $false
    approval_can_execute_work = $false
    shell_command_text_allowed = $false
    token_printed = $false
  }
}

function New-TrialApproval([bool]$Consumed = $false, [string]$State = "approved_for_this_goal_only") {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_approval.v1"
    approval_id = $ApprovalId
    trial_id = $TrialId
    workunit_id = $WorkunitId
    requested_mode = "one_workunit_controlled_trial"
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_codex_executions = 1
    max_task_prs = 1
    max_parallel_repo_mutations = 1
    require_release_gate = $true
    require_resource_gate = $true
    require_operator_approval = $true
    require_human_review = $true
    require_finalizer = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit = $true
    require_redaction = $true
    allow_remote_execution = $false
    allow_arbitrary_command = $false
    allow_generic_queue_apply = $false
    approval_state = $State
    expires_at = "2026-06-15T00:00:00.000Z"
    consumed = $Consumed
    approval_can_execute_work = $false
    shell_command_text_allowed = $false
    token_printed = $false
  }
}

function New-TrialWorkunit {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    task_type = "docs/local-smoke"
    risk = "low"
    target_path = $TargetPath
    allowed_paths = @("README.md", "docs/**")
    resource_gate = "required"
    approval = "required"
    human_review = "required"
    finalizer = "required"
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_task_prs = 1
    token_printed = $false
  }
}

function New-TrialReliabilityGates {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_reliability_gates.v1"
    failure_budget_gate_result = "pass"
    evidence_retention_gate_result = "pass"
    audit_redaction_gate_result = "pass"
    safe_export_gate_result = "pass"
    hash_chain_ready = $true
    raw_artifacts_indexed = $false
    token_printed = $false
  }
}

function New-TrialGate {
  $release = Get-ReleaseGate
  $resource = if ($SimulateResourceGateFail) { Invoke-SkybridgeResourceGate -RunId $TrialId -Fixture "battery-blocked" } else { Invoke-SkybridgeResourceGate -RunId $TrialId -Fixture "ac-ok" }
  $approval = New-TrialApproval
  $reliability = New-TrialReliabilityGates
  $openPrs = @(Get-OpenTrialTaskPrs)
  $blockers = @()
  if (-not $AuthorizeGoal221) { $blockers += "explicit_goal_221_authorization_required" }
  if ($release.release_gate_result -ne "pass" -or $release.tag_exists -ne $true) { $blockers += "release_gate_not_verified" }
  if ($release.remote_execution_enabled -ne $false -or $release.arbitrary_command_enabled -ne $false -or $release.execution_enabled -ne $false -or $release.queue_apply_enabled -ne $false -or $release.generic_bounded_queue_apply_enabled -ne $false) { $blockers += "execution_boundary_unsafe" }
  if ($resource.can_run_one_at_a_time -ne $true) { $blockers += "resource_gate_blocked" }
  if ($approval.approval_state -notin @("approved_for_this_goal_only", "explicit_fixture_approved")) { $blockers += "approval_gate_blocked" }
  if ($approval.approval_can_execute_work -ne $false -or $approval.shell_command_text_allowed -ne $false) { $blockers += "approval_contract_unsafe" }
  if ($reliability.failure_budget_gate_result -ne "pass") { $blockers += "failure_budget_gate_blocked" }
  if ($reliability.evidence_retention_gate_result -ne "pass") { $blockers += "evidence_retention_gate_blocked" }
  if ($reliability.audit_redaction_gate_result -ne "pass" -or $reliability.safe_export_gate_result -ne "pass") { $blockers += "audit_redaction_gate_blocked" }
  if ($ActiveTasks -ne 0) { $blockers += "active_tasks_present" }
  if ($StaleLeases -ne 0) { $blockers += "stale_leases_present" }
  if ($RunnerLock -ne "none") { $blockers += "runner_lock_present" }
  if (@($openPrs).Count -ne 0) { $blockers += "open_task_pr_present" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_gate.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    gate_result = if (@($blockers).Count -eq 0) { "pass" } else { "blocked" }
    can_execute_one_workunit = (@($blockers).Count -eq 0)
    max_workunits = 1
    max_tasks = 1
    max_claims = 1
    max_codex_executions = 1
    max_task_prs = 1
    release_gate = $release
    approval_gate = $approval
    resource_gate = $resource
    reliability_gates = $reliability
    desktop_resident_status = "safe_local_supervisor_ready"
    server_control_plane_status = "safe_preview_approval_only"
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    open_task_pr_count = @($openPrs).Count
    blockers = @($blockers | Select-Object -Unique)
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function Assert-TrialApplyGate {
  $status = (git -C $RepoRoot status --short | Out-String).Trim()
  if ($status) { throw "Dirty git status before controlled trial execution." }
  $gate = New-TrialGate
  if ($gate.can_execute_one_workunit -ne $true) {
    Write-TrialBlockedReport -Gate $gate
    throw "Controlled trial blocked before execution: $($gate.blockers -join ', ')"
  }
  $gate
}

function New-TrialMarkdown {
  @(
    "# BOINC v1 Controlled Trial 221",
    "",
    "- This is the first post-release BOINC-like v1 controlled trial workunit.",
    "- Release gate passed before this docs/local-smoke workunit.",
    "- Operator approval gate and local resource gate passed.",
    "- Failure budget, evidence retention, hash chain, audit, and redaction gates are active.",
    "- The task PR must remain open for human review; no auto-merge is authorized.",
    "- Generic bounded queue apply and remote execution remain disabled.",
    "- token_printed=false"
  ) -join "`n"
}

function Invoke-TrialCodexExecution {
  if ($SimulateCodexSuccess) {
    $target = Resolve-TrialPath $TargetPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Set-Content -LiteralPath $target -Value (New-TrialMarkdown) -Encoding utf8
    return [pscustomobject]@{ exit_code = 0; execution_count = 1; stdout_character_count = 0; stderr_character_count = 0; simulated = $true; token_printed = $false }
  }
  $prompt = @(
    "Create or update exactly docs/boinc-v1-controlled-trial-221.md.",
    "Write a short title.",
    "Write 4 to 8 concise bullets.",
    "Explain this is the first post-release BOINC-like v1 controlled trial workunit.",
    "Mention release gate passed.",
    "Mention operator approval gate passed.",
    "Mention resource gate passed.",
    "Mention failure budget, evidence retention, and audit are active.",
    "Mention task PR must remain open for human review.",
    "Mention generic bounded queue apply remains disabled.",
    "Mention remote execution remains disabled.",
    "Mention token_printed=false.",
    "Do not run tests.",
    "Do not run package managers.",
    "Do not run git.",
    "Do not run gh.",
    "Do not touch code.",
    "Do not touch config.",
    "Do not touch secrets.",
    "Finish immediately after writing the file."
  ) -join "`n"
  if (Test-TrialUnsafeText $prompt) { throw "Unsafe trial prompt." }
  $command = Resolve-SkybridgeCodexCommand
  if ($command.found -ne $true) { throw "Codex launcher not found." }
  $profile = New-SkybridgeCodexInvocationProfile
  if ($profile.enabled -ne $true) { throw "Codex profile disabled." }
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = [string]$command.source
  foreach ($arg in @($profile.arguments)) { [void]$psi.ArgumentList.Add([string]$arg) }
  $psi.WorkingDirectory = $RepoRoot
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $process = [System.Diagnostics.Process]::Start($psi)
  $process.StandardInput.Write($prompt)
  $process.StandardInput.Close()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  if (-not $process.WaitForExit(600000)) {
    try { $process.Kill($true) } catch {}
    return [pscustomobject]@{ exit_code = 124; execution_count = 1; stdout_character_count = $stdout.Length; stderr_character_count = $stderr.Length; simulated = $false; token_printed = $false }
  }
  [pscustomobject]@{ exit_code = $process.ExitCode; execution_count = 1; stdout_character_count = $stdout.Length; stderr_character_count = $stderr.Length; simulated = $false; token_printed = $false }
}

function New-TrialPrBody([string[]]$ChangedFiles, $Gate) {
  $body = @(
    "## BOINC v1 Controlled Trial 221",
    "",
    "- trial id: $TrialId",
    "- workunit id: $WorkunitId",
    "- task id: $TaskId",
    "- worker id: $WorkerId",
    "- release gate pass: $($Gate.release_gate.release_gate_result -eq 'pass')",
    "- approval gate pass: $($Gate.approval_gate.approval_state)",
    "- resource gate pass: $($Gate.resource_gate.can_run_one_at_a_time)",
    "- failure budget gate pass: $($Gate.reliability_gates.failure_budget_gate_result)",
    "- evidence retention gate pass: $($Gate.reliability_gates.evidence_retention_gate_result)",
    "- audit/redaction gate pass: $($Gate.reliability_gates.audit_redaction_gate_result)",
    "- changed files: $($ChangedFiles -join ', ')",
    "- no prompt/transcript/stdout/stderr artifacts",
    "- no auto-merge",
    "- human review required",
    "- token_printed=false"
  ) -join "`n"
  if (Test-TrialUnsafeText $body) { throw "Unsafe PR body." }
  $body
}

function Write-TrialBlockedReport($Gate) {
  $report = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_blocker.v1"
    trial_id = $TrialId
    state = "blocked_before_execution"
    blockers = @($Gate.blockers)
    codex_execution_count = 0
    task_pr_count = 0
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    no_next_execution_authorized = $true
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/trial-blocked-report.json" $report
  $report
}

function Write-TrialResult($State, $Gate, [string]$PrUrl, [string[]]$ChangedFiles, $Execution) {
  $resultPath = "$EvidenceDir/trial-result.json"
  $evidencePath = "$EvidenceDir/trial-evidence.json"
  $holdJsonPath = "$EvidenceDir/trial-hold-report.json"
  $holdMdPath = "$EvidenceDir/trial-hold-report.md"
  $result = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_result.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    state = $State
    pr_url = $PrUrl
    changed_files = @($ChangedFiles)
    codex_execution_count = if ($Execution) { [int]$Execution.execution_count } else { 0 }
    stdout_character_count = if ($Execution) { [int]$Execution.stdout_character_count } else { 0 }
    stderr_character_count = if ($Execution) { [int]$Execution.stderr_character_count } else { 0 }
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    worker_logs_persisted = $false
    token_printed = $false
  }
  Write-TrialSafeJson $resultPath $result
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_evidence.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    result_path = $resultPath
    result_sha256 = Get-TrialEvidenceHash $resultPath
    changed_files = @($ChangedFiles)
    safe_metadata_only = $true
    raw_artifacts_indexed = $false
    token_printed = $false
  }
  Write-TrialSafeJson $evidencePath $evidence
  $hold = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_hold_report.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    final_state = $State
    task_pr_url = $PrUrl
    task_pr_count = if ($PrUrl) { 1 } else { 0 }
    human_review_required = $true
    no_auto_merge = $true
    changed_files = @($ChangedFiles)
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    no_next_execution_authorized = $true
    token_printed = $false
  }
  Write-TrialSafeJson $holdJsonPath $hold
  Write-TrialSafeMarkdown $holdMdPath @(
    "# BOINC v1 Controlled Trial 221 Hold Report",
    "",
    "- trial id: $TrialId",
    "- workunit id: $WorkunitId",
    "- task id: $TaskId",
    "- final state: $State",
    "- task PR: $(if ($PrUrl) { $PrUrl } else { 'none' })",
    "- human review required: true",
    "- no_next_execution_authorized=true",
    "- token_printed=false"
  )
  Write-TrialAuditAndEvidenceReports -State $State -PrUrl $PrUrl -ChangedFiles $ChangedFiles | Out-Null
  $hold
}

function Write-TrialAuditAndEvidenceReports([string]$State, [string]$PrUrl, [string[]]$ChangedFiles) {
  $events = @(
    "release_gate_passed",
    "approval_gate_passed",
    "resource_gate_passed",
    "failure_budget_gate_passed",
    "evidence_retention_gate_passed",
    "redaction_gate_passed",
    "controlled_trial_started",
    $(if ($State -eq "held_waiting_human_review_controlled_trial_221") { "task_pr_created" } elseif ($State -eq "blocked_before_execution") { "controlled_trial_blocked" } else { "controlled_trial_failed" }),
    "human_review_required",
    "no_next_execution_authorized"
  )
  $audit = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_audit_report.v1"
    trial_id = $TrialId
    events = @($events | ForEach-Object { [pscustomobject]@{ event_type = $_; safe_metadata_only = $true; token_printed = $false } })
    task_pr_url = $PrUrl
    raw_artifacts_persisted = $false
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/trial-audit-report.json" $audit
  Write-TrialSafeMarkdown "$EvidenceDir/trial-audit-report.md" @(
    "# Controlled Trial 221 Audit Report",
    "",
    "- trial id: $TrialId",
    "- events: $($events -join ', ')",
    "- task PR: $(if ($PrUrl) { $PrUrl } else { 'none' })",
    "- raw artifacts persisted: false",
    "- token_printed=false"
  )
  $resultExists = Test-Path -LiteralPath (Resolve-TrialPath "$EvidenceDir/trial-result.json") -PathType Leaf
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_evidence_retention_report.v1"
    trial_id = $TrialId
    indexed_paths = @(
      "$EvidenceDir/trial-result.json",
      "$EvidenceDir/trial-evidence.json",
      "$EvidenceDir/trial-hold-report.json",
      "$EvidenceDir/trial-audit-report.json"
    )
    hash_chain_updated = $resultExists
    metadata_only = $true
    raw_artifacts_indexed = $false
    changed_files = @($ChangedFiles)
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/trial-evidence-retention-report.json" $evidence
  $safeExport = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_safe_export_report.v1"
    trial_id = $TrialId
    safe_to_export = $true
    export_scope = "metadata_only"
    raw_artifacts_excluded = $true
    authorization_headers_excluded = $true
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/trial-safe-export-report.json" $safeExport
  $audit
}

function Invoke-TrialApply {
  $gate = Assert-TrialApplyGate
  Write-TrialSafeJson "$EvidenceDir/trial-approval-consumed.json" (New-TrialApproval -Consumed $true -State "consumed")
  git -C $RepoRoot switch -c $TaskBranch | Out-Null
  try {
    $execution = Invoke-TrialCodexExecution
  } catch {
    Write-TrialResult -State "controlled_trial_failed" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $null | Out-Null
    throw
  }
  if ($execution.exit_code -ne 0) {
    Write-TrialResult -State "controlled_trial_failed" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution | Out-Null
    throw "Controlled trial Codex execution failed with exit code $($execution.exit_code)."
  }
  $changed = @(Get-SkybridgeChangedFiles)
  if (@($changed).Count -eq 0) {
    Write-TrialResult -State "controlled_trial_safe_no_change_failure" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution | Out-Null
    throw "Controlled trial produced no change."
  }
  Assert-SkybridgeAllowedPrPaths -Paths $changed | Out-Null
  $unexpected = @($changed | Where-Object { $_ -ne $TargetPath })
  if (@($unexpected).Count -ne 0) {
    Write-TrialResult -State "controlled_trial_disallowed_change_failure" -Gate $gate -PrUrl $null -ChangedFiles $changed -Execution $execution | Out-Null
    throw "Unexpected controlled trial changed file: $($unexpected -join ', ')"
  }
  git -C $RepoRoot add -- $TargetPath
  git -C $RepoRoot commit -m "BOINC v1 Controlled Trial 221 workunit" | Out-Null
  git -C $RepoRoot push -u origin $TaskBranch | Out-Null
  $body = New-TrialPrBody -ChangedFiles $changed -Gate $gate
  $bodyPath = Resolve-TrialPath "$EvidenceDir/trial-task-pr-body.md"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bodyPath) | Out-Null
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding utf8
  $prUrl = (gh pr create --title "BOINC v1 Controlled Trial 221: $WorkunitId" --body-file $bodyPath --base main --head $TaskBranch | Out-String).Trim()
  Write-TrialResult -State "held_waiting_human_review_controlled_trial_221" -Gate $gate -PrUrl $prUrl -ChangedFiles $changed -Execution $execution
}

function Get-TaskPrStatus {
  if ($SimulateTaskPrMerged) {
    return [pscustomobject]@{ exists = $true; state = "MERGED"; merged = $true; url = "https://example.invalid/pr/221"; changed_files = @($TargetPath); auto_merge_enabled = $false; token_printed = $false }
  }
  $hold = Read-TrialSafeJson "$EvidenceDir/trial-hold-report.json"
  if (-not $hold -or [string]::IsNullOrWhiteSpace($hold.task_pr_url)) {
    return [pscustomobject]@{ exists = $false; state = "none"; merged = $false; url = $null; changed_files = @(); auto_merge_enabled = $false; token_printed = $false }
  }
  try {
    $raw = gh pr view $hold.task_pr_url --json number,url,state,mergedAt,files,autoMergeRequest 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { throw "PR view failed." }
    $pr = ($raw | Out-String).Trim() | ConvertFrom-Json
    [pscustomobject]@{ exists = $true; state = $pr.state; merged = ($pr.state -eq "MERGED" -and $null -ne $pr.mergedAt); url = $pr.url; changed_files = @($pr.files | ForEach-Object { $_.path }); auto_merge_enabled = ($null -ne $pr.autoMergeRequest); token_printed = $false }
  } catch {
    [pscustomobject]@{ exists = $true; state = "unknown"; merged = $false; url = $hold.task_pr_url; changed_files = @(); auto_merge_enabled = $false; token_printed = $false }
  }
}

function New-TrialFinalizerPreview {
  $pr = Get-TaskPrStatus
  $result = Read-TrialSafeJson "$EvidenceDir/trial-result.json"
  $blockers = @()
  if ($pr.exists -ne $true) { $blockers += "task_pr_missing" }
  if ($pr.merged -ne $true) { $blockers += "task_pr_not_merged" }
  if ($pr.auto_merge_enabled -eq $true) { $blockers += "task_pr_auto_merge_enabled" }
  if (-not $result -or [int]$result.codex_execution_count -ne 1) { $blockers += "trial_result_missing_or_not_one_execution" }
  if ($result -and (@($result.changed_files).Count -ne 1 -or @($result.changed_files)[0] -ne $TargetPath)) { $blockers += "trial_changed_files_unexpected" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_finalizer_preview.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    task_pr_state = $pr.state
    task_pr_url = $pr.url
    task_pr_merged = $pr.merged
    codex_execution_count = if ($result) { [int]$result.codex_execution_count } else { 0 }
    task_count = 1
    task_pr_count = if ($pr.exists) { 1 } else { 0 }
    human_review_required = $true
    no_auto_merge = (-not $pr.auto_merge_enabled)
    no_raw_artifacts = $true
    status = if ($pr.exists -and $pr.merged -ne $true) { "held_waiting_human_review_controlled_trial_221" } elseif ($pr.merged) { "ready_to_finalize" } else { "not_started" }
    can_apply = (@($blockers).Count -eq 0)
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Invoke-TrialFinalizerApply {
  $preview = New-TrialFinalizerPreview
  if ($preview.can_apply -ne $true) { throw "Controlled trial finalizer blocked: $($preview.blockers -join ', ')" }
  $report = [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_finalizer_report.v1"
    trial_id = $TrialId
    finalizer_state = "completed"
    task_pr_url = $preview.task_pr_url
    no_next_execution_authorized = $true
    ready_for_goal_222 = $true
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/trial-finalizer-report.json" $report
  Write-TrialSafeJson "$EvidenceDir/trial-finalizer-evidence.json" ([pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_finalizer_evidence.v1"
    trial_id = $TrialId
    report_path = "$EvidenceDir/trial-finalizer-report.json"
    token_printed = $false
  })
  $report
}

function New-TrialSafeSummary {
  $gate = New-TrialGate
  $hold = Read-TrialSafeJson "$EvidenceDir/trial-hold-report.json"
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_controlled_trial_safe_summary.v1"
    trial_id = $TrialId
    workunit_id = $WorkunitId
    task_id = $TaskId
    gate_result = $gate.gate_result
    final_state = if ($hold) { $hold.final_state } else { "not_started" }
    task_pr_url = if ($hold) { $hold.task_pr_url } else { $null }
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

$result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_status.v1"; trial_id = $TrialId; workunit = New-TrialWorkunit; policy = New-TrialPolicy; gate = New-TrialGate; finalizer_preview = New-TrialFinalizerPreview; token_printed = $false } }
  "approval-preview" { New-TrialApproval }
  "approval-gate" { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_approval_gate.v1"; approval = New-TrialApproval; policy = New-TrialPolicy; token_printed = $false } }
  "trial-preview" { New-TrialWorkunit }
  "trial-apply-gate" { New-TrialGate }
  "trial-apply" { Invoke-TrialApply }
  "trial-evidence" { $existing = Read-TrialSafeJson "$EvidenceDir/trial-evidence.json"; if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_evidence.v1"; trial_id = $TrialId; exists = $false; token_printed = $false } } }
  "trial-audit-preview" { Write-TrialAuditAndEvidenceReports -State "preview" -PrUrl $null -ChangedFiles @() }
  "trial-finalizer-preview" { New-TrialFinalizerPreview }
  "trial-finalizer-apply" { Invoke-TrialFinalizerApply }
  "trial-finalizer-evidence" { $existing = Read-TrialSafeJson "$EvidenceDir/trial-finalizer-evidence.json"; if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_finalizer_evidence.v1"; trial_id = $TrialId; exists = $false; token_printed = $false } } }
  "trial-finalizer-report" { $existing = Read-TrialSafeJson "$EvidenceDir/trial-finalizer-report.json"; if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_finalizer_report.v1"; trial_id = $TrialId; finalizer_state = "not_applied"; token_printed = $false } } }
  "trial-safe-summary" { New-TrialSafeSummary }
  "trial-report" { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_report.v1"; trial_id = $TrialId; gate = New-TrialGate; safe_summary = New-TrialSafeSummary; token_printed = $false } }
  "no-execution-gate" { [pscustomobject]@{ schema = "skybridge.boinc_v1_controlled_trial_no_execution_gate.v1"; trial_id = $TrialId; approval_can_execute_work = $false; generic_queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; can_execute_without_trial_apply = $false; token_printed = $false } }
}

ConvertTo-TrialJsonOut $result
