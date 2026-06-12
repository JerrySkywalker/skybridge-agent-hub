[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "alpha-preview", "alpha-apply-gate", "alpha-workunit-a-preview", "alpha-workunit-b-preview", "alpha-workunit-a-apply", "alpha-safe-summary", "alpha-report", "alpha-hold-report", "evidence", "blocked-state", "workunit-a-finalizer-preview", "workunit-a-finalizer-apply", "workunit-a-finalizer-evidence", "workunit-a-finalizer-report", "workunit-b-apply-gate", "workunit-b-apply", "workunit-b-hold-report", "workunit-b-finalizer-preview", "workunit-b-finalizer-apply", "workunit-b-finalizer-evidence", "workunit-b-finalizer-report", "alpha-completion-readiness")]
  [string]$Command,

  [switch]$AuthorizeGoal215,
  [switch]$AuthorizeGoal216,
  [switch]$SimulateResourceGateFail,
  [switch]$SimulateOpenReview,
  [switch]$SimulateCodexSuccess,
  [switch]$SimulatePackaging,
  [switch]$SimulatePr157Merged,
  [switch]$SimulateWorkunitAFinalized,
  [switch]$SimulateWorkunitBExecuted,
  [switch]$SimulateWorkunitBPrMerged,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$EvidenceDir = ".agent/tmp/boinc-v1-alpha-215",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.CodexExecutor.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.ResourceGate.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.WorkunitRegistry.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.EvidenceStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.PrPackager.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.QueuePolicy.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.SafetyScanner.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.SmokeHarness.psm1") -Force

$AlphaId = "boinc-v1-alpha-215"
$WorkunitAId = "boinc-v1-alpha-215-workunit-a"
$WorkunitBId = "boinc-v1-alpha-215-workunit-b"
$TaskAId = "boinc-v1-alpha-215-task-a"
$TaskBId = "boinc-v1-alpha-215-task-b"
$TargetA = "docs/boinc-v1-alpha-workunit-a.md"
$TargetB = "docs/boinc-v1-alpha-workunit-b.md"
$TaskBranch = "ai/boinc-v1-alpha/boinc-v1-alpha-215-workunit-a"
$TaskBranchB = "ai/boinc-v1-alpha/boinc-v1-alpha-215-workunit-b"
$WorkunitAPrNumber = 157

function Get-AlphaRepoRoot {
  (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}

function Resolve-AlphaPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Get-AlphaRepoRoot) $Path))
}

function Test-AlphaUnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout(?!_persisted)|raw_stderr(?!_persisted)|raw_prompt(?!_persisted)|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Write-AlphaSafeJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
  $full = Resolve-AlphaPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $json = $Value | ConvertTo-Json -Depth 14
  if (Test-AlphaUnsafeText $json) { throw "Unsafe JSON evidence." }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function Read-AlphaSafeJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-AlphaPath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $full
  if (Test-AlphaUnsafeText $text) { throw "Unsafe JSON evidence." }
  $text | ConvertFrom-Json
}

function Get-AlphaEvidenceHash {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Resolve-AlphaPath $Path
  (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-JsonOut {
  param($Value)
  if ($Json) { $Value | ConvertTo-Json -Depth 14 } else { $Value }
}

function Test-OpenAlphaPr {
  if ($SimulateOpenReview) { return 1 }
  try {
    $raw = gh pr list --state open --search "boinc-v1-alpha-215 OR managed-mode OR BOINC" --json number,title,url,headRefName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String))) { return 0 }
    $items = ($raw | Out-String).Trim() | ConvertFrom-Json
    return @($items).Count
  } catch {
    return 0
  }
}

function Get-ResourceGate {
  if ($SimulateResourceGateFail) { return Invoke-SkybridgeResourceGate -RunId $AlphaId -Fixture "battery-blocked" }
  Invoke-SkybridgeResourceGate -RunId $AlphaId -Fixture "ac-ok"
}

function Get-WorkerReadiness {
  $plan = New-SkybridgeCodexExecutionPlan -Prompt "" -FixtureCommands @("C:/tools/codex.exe")
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_worker_readiness.v1"
    worker_id = $WorkerId
    task_type = "docs/local-smoke"
    risk = "low"
    can_execute_one_alpha_workunit = $true
    codex_launcher_classification = $plan.resolved.launcher_kind
    generic_scheduler_apply_enabled = $false
    token_printed = $false
  }
}

function New-AlphaPolicy {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_policy.v1"
    alpha_id = $AlphaId
    alpha_mode = "controlled_two_workunit_alpha"
    max_preview_workunits = 2
    max_apply_workunits_for_this_goal = 1
    general_apply_enabled = $false
    workunit_b_apply_enabled = $false
    require_resource_gate = $true
    require_worker_readiness = $true
    require_human_review = $true
    serialize_repo_mutations = $true
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    token_printed = $false
  }
}

function New-AlphaWorkunit {
  param([ValidateSet("A", "B")][string]$Which)
  if ($Which -eq "A") {
    return [pscustomobject]@{
      schema = "skybridge.boinc_v1_alpha_workunit.v1"
      alpha_id = $AlphaId
      workunit_id = $WorkunitAId
      task_id = $TaskAId
      target_path = $TargetA
      task_type = "docs/local-smoke"
      risk = "low"
      dependency = "none"
      status = "ready_if_gates_pass"
      apply_enabled_for_this_goal = [bool]$AuthorizeGoal215
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitBId
    task_id = $TaskBId
    target_path = $TargetB
    task_type = "docs/local-smoke"
    risk = "low"
    dependency = "Workunit A completed and finalized"
    status = "blocked_by_unfinalized_workunit_a"
    apply_enabled_for_this_goal = $false
    token_printed = $false
  }
}

function New-AlphaPreview {
  $a = New-AlphaWorkunit -Which A
  $b = New-AlphaWorkunit -Which B
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_preview.v1"
    alpha_id = $AlphaId
    policy = New-AlphaPolicy
    workunits = @($a, $b)
    preview_workunit_count = 2
    max_workunits_preview = 2
    workunit_a_target_valid = ($a.target_path -eq $TargetA)
    workunit_b_target_valid = ($b.target_path -eq $TargetB)
    workunit_b_blocked = $true
    workunit_b_blocked_reason = "blocked_by_unfinalized_workunit_a"
    general_apply_enabled = $false
    multi_workunit_apply_enabled = $false
    token_printed = $false
  }
}

function New-AlphaApplyGate {
  $resourceGate = Get-ResourceGate
  $worker = Get-WorkerReadiness
  $registry = Get-SkybridgeRunRegistrySummary -ActiveTasks $ActiveTasks -StaleLeases $StaleLeases -RunnerLock $RunnerLock -OpenManagedModePrCount (Test-OpenAlphaPr)
  $preview = New-AlphaPreview
  $blockers = @()
  if (-not $AuthorizeGoal215) { $blockers += "explicit_goal_215_authorization_required" }
  if ($resourceGate.can_run_one_at_a_time -ne $true) { $blockers += "resource_gate_blocked" }
  if ($worker.can_execute_one_alpha_workunit -ne $true) { $blockers += "worker_readiness_failed" }
  if ($registry.completed_run_count -ne 4) { $blockers += "completed_run_registry_incomplete" }
  if ($registry.active_tasks -ne 0) { $blockers += "active_tasks_present" }
  if ($registry.stale_leases -ne 0) { $blockers += "stale_leases_present" }
  if ($registry.runner_lock -ne "none") { $blockers += "runner_lock_present" }
  if ($registry.open_review_hold) { $blockers += "open_review_hold" }
  if ($preview.preview_workunit_count -ne 2) { $blockers += "unexpected_workunit_count" }
  if ($preview.workunit_b_blocked -ne $true) { $blockers += "workunit_b_not_blocked" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_apply_gate.v1"
    alpha_id = $AlphaId
    can_apply_workunit_a = (@($blockers).Count -eq 0)
    can_apply_workunit_b = $false
    allowed_workunit_ids = if (@($blockers).Count -eq 0) { @($WorkunitAId) } else { @() }
    blocked_workunit_ids = @($WorkunitBId)
    workunit_b_blocked_reason = "blocked_by_unfinalized_workunit_a"
    max_apply_workunits = 1
    max_workunits_preview = 2
    general_apply_enabled = $false
    multi_workunit_apply_enabled = $false
    resource_gate = $resourceGate
    worker_readiness = $worker
    registry_summary = $registry
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Assert-GateForApply {
  $status = git status --short
  if (-not [string]::IsNullOrWhiteSpace(($status | Out-String).Trim())) { throw "Dirty git status before execution." }
  $gate = New-AlphaApplyGate
  if ($gate.can_apply_workunit_a -ne $true) {
    Write-AlphaResult -State "boinc_v1_alpha_215_blocked_before_execution" -Gate $gate -PrUrl $null -ChangedFiles @() | Out-Null
    throw "Alpha Workunit A gate blocked: $($gate.blockers -join ', ')"
  }
  if ($gate.can_apply_workunit_b -ne $false -or @($gate.allowed_workunit_ids) -contains $WorkunitBId) { throw "Workunit B must remain blocked." }
  $gate
}

function New-WorkunitAMarkdown {
  @(
    "# BOINC v1 Alpha Workunit A",
    "",
    "- This document was created by BOINC-like v1 alpha Workunit A.",
    "- Workunit B is blocked until Workunit A is human-reviewed, merged, and finalized.",
    "- The resource gate passed before this Workunit A execution.",
    "- General bounded queue apply remains disabled.",
    "- token_printed=false"
  ) -join "`n"
}

function Invoke-CodexForWorkunitA {
  if ($SimulateCodexSuccess) {
  $target = Resolve-AlphaPath $TargetA
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Set-Content -LiteralPath $target -Value (New-WorkunitAMarkdown) -Encoding utf8
    return [pscustomobject]@{ exit_code = 0; execution_count = 1; stdout_character_count = 0; stderr_character_count = 0; simulated = $true; token_printed = $false }
  }

  $command = Resolve-SkybridgeCodexCommand
  if ($command.found -ne $true) { throw "Codex launcher not found." }
  $profile = New-SkybridgeCodexInvocationProfile
  if ($profile.enabled -ne $true) { throw "Codex profile disabled." }
  $prompt = @(
    "Create or update exactly docs/boinc-v1-alpha-workunit-a.md.",
    "Write a short title and 3-6 concise bullets.",
    "Explain this is BOINC-like v1 alpha Workunit A.",
    "Mention Workunit B is blocked until A is human-reviewed and finalized.",
    "Mention resource gate passed, general bounded queue apply remains disabled, and token_printed=false.",
    "Do not run tests, package managers, git, or gh. Do not touch code, config, or secrets. Finish immediately after writing the file."
  ) -join "`n"
  if (Test-AlphaUnsafeText $prompt) { throw "Unsafe prompt text." }

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = [string]$command.source
  foreach ($arg in @($profile.arguments)) { [void]$psi.ArgumentList.Add([string]$arg) }
  $psi.WorkingDirectory = Get-AlphaRepoRoot
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

function New-TaskPrBody {
  param([string[]]$ChangedFiles, [object]$Gate)
  $body = @(
    "## BOINC v1 Alpha 215 Workunit A",
    "",
    "- alpha id: $AlphaId",
    "- workunit id: $WorkunitAId",
    "- task id: $TaskAId",
    "- worker id: $WorkerId",
    "- resource gate pass: $($Gate.resource_gate.can_run_one_at_a_time)",
    "- Workunit B blocked until A finalizer: true",
    "- changed files: $($ChangedFiles -join ', ')",
    "- no raw prompt/transcript/stdout/stderr",
    "- no auto-merge",
    "- token_printed=false"
  ) -join "`n"
  if (Test-AlphaUnsafeText $body) { throw "Unsafe PR body." }
  $body
}

function Get-Pr157Status {
  if ($SimulatePr157Merged) {
    return [pscustomobject]@{
      number = $WorkunitAPrNumber
      state = "MERGED"
      merged = $true
      merge_commit = "fixture-workunit-a-merge"
      changed_files = @($TargetA)
      auto_merge_enabled = $false
      url = "https://example.invalid/skybridge-agent-hub/pull/157"
      token_printed = $false
    }
  }
  try {
    $raw = gh pr view $WorkunitAPrNumber --json number,url,state,mergedAt,mergeCommit,files,autoMergeRequest 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { throw "PR view failed." }
    $pr = ($raw | Out-String).Trim() | ConvertFrom-Json
    [pscustomobject]@{
      number = $pr.number
      state = $pr.state
      merged = ($pr.state -eq "MERGED" -and $null -ne $pr.mergedAt)
      merge_commit = if ($pr.mergeCommit) { $pr.mergeCommit.oid } else { $null }
      changed_files = @($pr.files | ForEach-Object { $_.path })
      auto_merge_enabled = ($null -ne $pr.autoMergeRequest)
      url = $pr.url
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{
      number = $WorkunitAPrNumber
      state = "unknown"
      merged = $false
      merge_commit = $null
      changed_files = @()
      auto_merge_enabled = $false
      url = $null
      token_printed = $false
    }
  }
}

function Test-AlphaEvidenceTreeSafe {
  $full = Resolve-AlphaPath $EvidenceDir
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
  $files = @(Get-ChildItem -LiteralPath $full -File -Recurse)
  foreach ($file in $files) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if (Test-AlphaUnsafeText $text) { return $false }
  }
  $true
}

function Test-WorkunitAFinalized {
  if ($SimulateWorkunitAFinalized) { return $true }
  $report = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-finalizer-report.json"
  return ($null -ne $report -and $report.workunit_a_completed -eq $true)
}

function Test-WorkunitBExecuted {
  if ($SimulateWorkunitBExecuted) { return $true }
  $result = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-result.json"
  return ($null -ne $result -and [int]$result.codex_execution_count -eq 1)
}

function Get-WorkunitBPrStatus {
  if ($SimulateWorkunitBPrMerged) {
    return [pscustomobject]@{ exists = $true; state = "MERGED"; merged = $true; url = "https://example.invalid/skybridge-agent-hub/pull/216"; changed_files = @($TargetB); auto_merge_enabled = $false; token_printed = $false }
  }
  try {
    $raw = gh pr list --state all --head $TaskBranchB --json number,url,state,mergedAt,files,autoMergeRequest 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { throw "PR list failed." }
    $items = @((($raw | Out-String).Trim() | ConvertFrom-Json))
    if ($items.Count -eq 0) { throw "No Workunit B PR." }
    $pr = $items[0]
    [pscustomobject]@{
      exists = $true
      state = $pr.state
      merged = ($pr.state -eq "MERGED" -and $null -ne $pr.mergedAt)
      url = $pr.url
      changed_files = @($pr.files | ForEach-Object { $_.path })
      auto_merge_enabled = ($null -ne $pr.autoMergeRequest)
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{ exists = $false; state = "none"; merged = $false; url = $null; changed_files = @(); auto_merge_enabled = $false; token_printed = $false }
  }
}

function New-WorkunitAFinalizerPreview {
  $pr = Get-Pr157Status
  $result = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-result.json"
  $evidence = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-evidence.json"
  $hold = Read-AlphaSafeJson -Path "$EvidenceDir/alpha-hold-report.json"
  $blockers = @()
  if ($pr.merged -ne $true) { $blockers += "workunit_a_pr_not_merged" }
  if (-not (Test-Path -LiteralPath (Resolve-AlphaPath $TargetA) -PathType Leaf)) { $blockers += "workunit_a_changed_file_missing_on_main" }
  if ($null -eq $result -or $result.workunit_id -ne $WorkunitAId -or [int]$result.codex_execution_count -ne 1) { $blockers += "workunit_a_result_unsafe_or_ambiguous" }
  if ($null -eq $evidence -or $evidence.workunit_id -ne $WorkunitAId) { $blockers += "workunit_a_evidence_missing" }
  if ($null -eq $hold -or $hold.workunit_a_state -ne "held_waiting_human_pr_review_workunit_a") { $blockers += "workunit_a_hold_missing" }
  if (-not (Test-AlphaEvidenceTreeSafe)) { $blockers += "alpha_evidence_tree_unsafe" }
  if ($pr.auto_merge_enabled -eq $true) { $blockers += "workunit_a_auto_merge_enabled" }
  if (@($pr.changed_files).Count -ne 1 -or @($pr.changed_files)[0] -ne $TargetA) { $blockers += "workunit_a_changed_files_unexpected" }
  if (Test-WorkunitBExecuted) { $blockers += "workunit_b_already_executed" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_a_finalizer_preview.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitAId
    task_id = $TaskAId
    pr_number = $WorkunitAPrNumber
    pr_merged = $pr.merged
    merge_commit = $pr.merge_commit
    changed_file = $TargetA
    codex_execution_count = if ($result) { [int]$result.codex_execution_count } else { 0 }
    task_pr_count = 1
    workunit_b_executed = Test-WorkunitBExecuted
    auto_merge_enabled = $pr.auto_merge_enabled
    human_review_confirmed = $pr.merged
    can_apply = (@($blockers).Count -eq 0)
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Invoke-WorkunitAFinalizerApply {
  $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-finalizer-report.json"
  if ($existing -and $existing.workunit_a_completed -eq $true) { throw "Workunit A finalizer already applied." }
  $preview = New-WorkunitAFinalizerPreview
  if ($preview.can_apply -ne $true) { throw "Workunit A finalizer blocked: $($preview.blockers -join ', ')" }
  $evidencePath = "$EvidenceDir/workunit-a-finalizer-evidence.json"
  $reportPath = "$EvidenceDir/workunit-a-finalizer-report.json"
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_a_finalizer_evidence.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitAId
    task_id = $TaskAId
    pr_number = $WorkunitAPrNumber
    pr_merged = $true
    merge_commit = $preview.merge_commit
    changed_file = $TargetA
    result_sha256 = Get-AlphaEvidenceHash "$EvidenceDir/workunit-a-result.json"
    evidence_tree_safe = $true
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $evidencePath -Value $evidence
  $report = [pscustomObject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_a_finalizer_report.v1"
    alpha_id = $AlphaId
    workunit_a_completed = $true
    workunit_a_rerun_blocked = $true
    workunit_b_state = "pending_gates"
    finalizer_evidence_path = $evidencePath
    finalizer_evidence_sha256 = Get-AlphaEvidenceHash $evidencePath
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $reportPath -Value $report
  $report
}

function New-WorkunitBApplyGate {
  $resourceGate = Get-ResourceGate
  $worker = Get-WorkerReadiness
  $registry = Get-SkybridgeRunRegistrySummary -ActiveTasks $ActiveTasks -StaleLeases $StaleLeases -RunnerLock $RunnerLock -OpenManagedModePrCount (Test-OpenAlphaPr)
  $blockers = @()
  if (-not $AuthorizeGoal216) { $blockers += "explicit_goal_216_authorization_required" }
  if (-not (Test-WorkunitAFinalized)) { $blockers += "workunit_a_finalizer_required" }
  if (Test-WorkunitBExecuted) { $blockers += "workunit_b_already_executed" }
  if ($resourceGate.can_run_one_at_a_time -ne $true) { $blockers += "resource_gate_blocked" }
  if (@($resourceGate.warnings).Count -gt 0) { $blockers += "resource_gate_warning" }
  if ($worker.can_execute_one_alpha_workunit -ne $true) { $blockers += "worker_readiness_failed" }
  if ($registry.active_tasks -ne 0) { $blockers += "active_tasks_present" }
  if ($registry.stale_leases -ne 0) { $blockers += "stale_leases_present" }
  if ($registry.runner_lock -ne "none") { $blockers += "runner_lock_present" }
  if ($registry.open_review_hold) { $blockers += "open_review_hold" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_apply_gate.v1"
    alpha_id = $AlphaId
    can_apply_workunit_b = (@($blockers).Count -eq 0)
    allowed_workunit_ids = if (@($blockers).Count -eq 0) { @($WorkunitBId) } else { @() }
    max_apply_workunits = 1
    workunit_c_present = $false
    general_apply_enabled = $false
    multi_workunit_apply_enabled = $false
    resource_gate = $resourceGate
    worker_readiness = $worker
    registry_summary = $registry
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-WorkunitBMarkdown {
  @(
    "# BOINC v1 Alpha Workunit B",
    "",
    "- This document was created by BOINC-like v1 alpha Workunit B.",
    "- Workunit A was finalized before Workunit B ran.",
    "- Repo-mutating work is serialized and human review is required before completion.",
    "- General bounded queue apply remains disabled.",
    "- token_printed=false"
  ) -join "`n"
}

function Invoke-CodexForWorkunitB {
  if ($SimulateCodexSuccess) {
    $target = Resolve-AlphaPath $TargetB
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Set-Content -LiteralPath $target -Value (New-WorkunitBMarkdown) -Encoding utf8
    return [pscustomobject]@{ exit_code = 0; execution_count = 1; stdout_character_count = 0; stderr_character_count = 0; simulated = $true; token_printed = $false }
  }

  $command = Resolve-SkybridgeCodexCommand
  if ($command.found -ne $true) { throw "Codex launcher not found." }
  $profile = New-SkybridgeCodexInvocationProfile
  if ($profile.enabled -ne $true) { throw "Codex profile disabled." }
  $prompt = @(
    "Create or update exactly docs/boinc-v1-alpha-workunit-b.md.",
    "Write a short title and 3 to 6 concise bullets.",
    "Explain this is BOINC-like v1 alpha Workunit B.",
    "Mention Workunit A was finalized before B ran.",
    "Mention repo-mutating work is serialized and human review is required before completion.",
    "Mention general bounded queue apply remains disabled and token_printed=false.",
    "Do not run tests, package managers, git, or gh. Do not touch code, config, or secrets. Finish after writing the file."
  ) -join "`n"
  if (Test-AlphaUnsafeText $prompt) { throw "Unsafe prompt text." }

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = [string]$command.source
  foreach ($arg in @($profile.arguments)) { [void]$psi.ArgumentList.Add([string]$arg) }
  $psi.WorkingDirectory = Get-AlphaRepoRoot
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

function New-WorkunitBTaskPrBody {
  param([string[]]$ChangedFiles, [object]$Gate)
  $body = @(
    "## BOINC v1 Alpha 215 Workunit B",
    "",
    "- alpha id: $AlphaId",
    "- Workunit A finalizer evidence path: $EvidenceDir/workunit-a-finalizer-evidence.json",
    "- Workunit B id: $WorkunitBId",
    "- Workunit B task id: $TaskBId",
    "- worker id: $WorkerId",
    "- resource gate pass: $($Gate.resource_gate.can_run_one_at_a_time)",
    "- changed files: $($ChangedFiles -join ', ')",
    "- no raw prompt/transcript/stdout/stderr",
    "- no auto-merge",
    "- token_printed=false"
  ) -join "`n"
  if (Test-AlphaUnsafeText $body) { throw "Unsafe PR body." }
  $body
}

function Write-WorkunitBResult {
  param([string]$State, $Gate, [string]$PrUrl, [string[]]$ChangedFiles = @(), $Execution = $null)
  $resultPath = "$EvidenceDir/workunit-b-result.json"
  $evidencePath = "$EvidenceDir/workunit-b-evidence.json"
  $holdJsonPath = "$EvidenceDir/workunit-b-hold-report.json"
  $holdMdPath = "$EvidenceDir/workunit-b-hold-report.md"
  $result = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_result.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitBId
    task_id = $TaskBId
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
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $resultPath -Value $result
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_evidence.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitBId
    task_id = $TaskBId
    result_path = $resultPath
    result_sha256 = Get-AlphaEvidenceHash $resultPath
    state = $State
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $evidencePath -Value $evidence
  $hold = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_hold_report.v1"
    alpha_id = $AlphaId
    workunit_a_state = "completed"
    workunit_b_state = $State
    open_task_pr_url = $PrUrl
    changed_files = @($ChangedFiles)
    next_required_human_action = if ($PrUrl) { "Review and merge Workunit B task PR, then run a later finalizer goal." } else { "Inspect controlled Workunit B failure before retry authorization." }
    resource_gate_status = $Gate.resource_gate
    no_next_execution_authorized = $true
    workunit_c_present = $false
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $holdJsonPath -Value $hold
  $md = @(
    "# BOINC v1 Alpha 215 Workunit B Hold Report",
    "",
    "- alpha id: $AlphaId",
    "- Workunit A state: completed",
    "- Workunit B state: $State",
    "- open task PR: $(if ($PrUrl) { $PrUrl } else { 'none' })",
    "- Workunit C present: false",
    "- token_printed=false"
  ) -join "`n"
  if (Test-AlphaUnsafeText $md) { throw "Unsafe Workunit B hold markdown." }
  $fullMd = Resolve-AlphaPath $holdMdPath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullMd) | Out-Null
  Set-Content -LiteralPath $fullMd -Value $md -Encoding utf8
  $hold
}

function Invoke-WorkunitBApply {
  $status = git status --short
  if (-not [string]::IsNullOrWhiteSpace(($status | Out-String).Trim())) { throw "Dirty git status before Workunit B execution." }
  $gate = New-WorkunitBApplyGate
  if ($gate.can_apply_workunit_b -ne $true) {
    Write-WorkunitBResult -State "boinc_v1_alpha_215_workunit_b_blocked_before_execution" -Gate $gate -PrUrl $null -ChangedFiles @() | Out-Null
    throw "Workunit B gate blocked: $($gate.blockers -join ', ')"
  }
  git switch -c $TaskBranchB | Out-Null
  try {
    $execution = Invoke-CodexForWorkunitB
  } catch {
    Write-WorkunitBResult -State "boinc_v1_alpha_215_workunit_b_failed" -Gate $gate -PrUrl $null -ChangedFiles @() | Out-Null
    throw "Workunit B Codex execution failed before launch."
  }
  if ($execution.exit_code -ne 0) {
    Write-WorkunitBResult -State "boinc_v1_alpha_215_workunit_b_failed" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution | Out-Null
    throw "Workunit B Codex execution failed with exit code $($execution.exit_code)."
  }
  $changed = @(Get-SkybridgeChangedFiles)
  if ($changed.Count -eq 0) {
    Write-WorkunitBResult -State "boinc_v1_alpha_215_workunit_b_no_change" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution | Out-Null
    throw "Workunit B produced no changes."
  }
  Assert-SkybridgeAllowedPrPaths -Paths $changed | Out-Null
  $bad = @($changed | Where-Object { $_ -ne $TargetB })
  if ($bad.Count -gt 0) {
    Write-WorkunitBResult -State "boinc_v1_alpha_215_workunit_b_disallowed_change" -Gate $gate -PrUrl $null -ChangedFiles $changed -Execution $execution | Out-Null
    throw "Unexpected changed file for Workunit B: $($bad -join ', ')"
  }
  git add -- $TargetB
  git commit -m "BOINC v1 Alpha 215 Workunit B" | Out-Null
  git push -u origin $TaskBranchB | Out-Null
  $body = New-WorkunitBTaskPrBody -ChangedFiles $changed -Gate $gate
  $bodyPath = Resolve-AlphaPath "$EvidenceDir/workunit-b-pr-body.md"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bodyPath) | Out-Null
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding utf8
  $prUrl = (gh pr create --title "BOINC v1 Alpha 215 Workunit B: $WorkunitBId" --body-file $bodyPath --base main --head $TaskBranchB | Out-String).Trim()
  $hold = Write-WorkunitBResult -State "held_waiting_human_pr_review_workunit_b" -Gate $gate -PrUrl $prUrl -ChangedFiles $changed -Execution $execution
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_apply_result.v1"
    alpha_id = $AlphaId
    workunit_b_id = $WorkunitBId
    state = "held_waiting_human_pr_review_workunit_b"
    pr_url = $prUrl
    changed_files = $changed
    codex_execution_count = 1
    hold_report = $hold
    token_printed = $false
  }
}

function New-WorkunitBFinalizerPreview {
  $pr = Get-WorkunitBPrStatus
  $result = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-result.json"
  $blockers = @()
  if (-not (Test-WorkunitAFinalized)) { $blockers += "workunit_a_finalizer_required" }
  if (-not $pr.exists) { $blockers += "workunit_b_pr_missing" }
  if ($pr.exists -and $pr.merged -ne $true) { $blockers += "workunit_b_pr_not_merged" }
  if ($null -eq $result -and -not $SimulateWorkunitBExecuted) { $blockers += "workunit_b_result_missing" }
  if (-not (Test-AlphaEvidenceTreeSafe)) { $blockers += "alpha_evidence_tree_unsafe" }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_finalizer_preview.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitBId
    pr_state = $pr.state
    status = if ($pr.exists -and $pr.merged -ne $true) { "held_waiting_human_pr_review_workunit_b" } elseif ($pr.merged) { "ready_to_finalize" } else { "not_started" }
    can_apply = (@($blockers).Count -eq 0)
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Invoke-WorkunitBFinalizerApply {
  $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-finalizer-report.json"
  if ($existing -and $existing.workunit_b_completed -eq $true) { throw "Workunit B finalizer already applied." }
  $preview = New-WorkunitBFinalizerPreview
  if ($preview.can_apply -ne $true) { throw "Workunit B finalizer blocked: $($preview.blockers -join ', ')" }
  if (-not (Test-Path -LiteralPath (Resolve-AlphaPath $TargetB) -PathType Leaf)) { throw "Workunit B changed file missing on main." }
  $evidencePath = "$EvidenceDir/workunit-b-finalizer-evidence.json"
  $reportPath = "$EvidenceDir/workunit-b-finalizer-report.json"
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_finalizer_evidence.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitBId
    changed_file = $TargetB
    result_sha256 = Get-AlphaEvidenceHash "$EvidenceDir/workunit-b-result.json"
    evidence_tree_safe = $true
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $evidencePath -Value $evidence
  $report = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_b_finalizer_report.v1"
    alpha_id = $AlphaId
    workunit_b_completed = $true
    workunit_b_rerun_blocked = $true
    two_workunit_alpha_completed = $true
    finalizer_evidence_path = $evidencePath
    finalizer_evidence_sha256 = Get-AlphaEvidenceHash $evidencePath
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $reportPath -Value $report
  $report
}

function New-AlphaCompletionReadiness {
  $aFinalized = Test-WorkunitAFinalized
  $bResult = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-result.json"
  $bFinalized = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-finalizer-report.json"
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_215_completion_readiness.v1"
    alpha_id = $AlphaId
    readiness_state = if ($bFinalized -and $bFinalized.two_workunit_alpha_completed -eq $true) { "boinc_v1_alpha_two_workunit_completed" } elseif ($bResult -and $bResult.state -eq "held_waiting_human_pr_review_workunit_b") { "boinc_v1_alpha_waiting_for_workunit_b_human_review" } elseif ($aFinalized) { "workunit_a_completed_workunit_b_pending" } else { "workunit_a_finalizer_pending" }
    workunit_a_completed = $aFinalized
    workunit_b_state = if ($bResult) { $bResult.state } else { "not_executed" }
    workunit_c_present = $false
    general_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function Write-AlphaResult {
  param([string]$State, $Gate, [string]$PrUrl, [string[]]$ChangedFiles = @(), $Execution = $null)
  $evidencePath = "$EvidenceDir/workunit-a-evidence.json"
  $resultPath = "$EvidenceDir/workunit-a-result.json"
  $holdJsonPath = "$EvidenceDir/alpha-hold-report.json"
  $holdMdPath = "$EvidenceDir/alpha-hold-report.md"
  $result = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_a_result.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitAId
    task_id = $TaskAId
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
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $resultPath -Value $result
  $evidence = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_workunit_a_evidence.v1"
    alpha_id = $AlphaId
    workunit_id = $WorkunitAId
    task_id = $TaskAId
    result_path = $resultPath
    result_sha256 = Get-AlphaEvidenceHash $resultPath
    state = $State
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $evidencePath -Value $evidence
  $hold = [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_hold_report.v1"
    alpha_id = $AlphaId
    workunit_a_state = $State
    workunit_b_state = "blocked_by_unfinalized_workunit_a"
    workunit_b_blocked_reason = "blocked_by_unfinalized_workunit_a"
    open_task_pr_url = $PrUrl
    changed_files = @($ChangedFiles)
    next_required_human_action = if ($PrUrl) { "Review and merge Workunit A task PR, then run Goal 216." } else { "Inspect controlled failure before retry authorization." }
    resource_gate_status = $Gate.resource_gate
    no_next_execution_authorized = $true
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    token_printed = $false
  }
  Write-AlphaSafeJson -Path $holdJsonPath -Value $hold
  $md = @(
    "# BOINC v1 Alpha 215 Hold Report",
    "",
    "- alpha id: $AlphaId",
    "- Workunit A state: $State",
    "- Workunit B state: blocked_by_unfinalized_workunit_a",
    "- open task PR: $(if ($PrUrl) { $PrUrl } else { 'none' })",
    "- next required human action: $($hold.next_required_human_action)",
    "- token_printed=false"
  ) -join "`n"
  if (Test-AlphaUnsafeText $md) { throw "Unsafe hold markdown." }
  $fullMd = Resolve-AlphaPath $holdMdPath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullMd) | Out-Null
  Set-Content -LiteralPath $fullMd -Value $md -Encoding utf8
  $hold
}

function Invoke-WorkunitAApply {
  $gate = Assert-GateForApply
  git switch -c $TaskBranch | Out-Null
  try {
    $execution = Invoke-CodexForWorkunitA
  } catch {
    Write-AlphaResult -State "boinc_v1_alpha_215_workunit_a_failed" -Gate $gate -PrUrl $null -ChangedFiles @() | Out-Null
    throw "Codex execution failed before launch."
  }
  if ($execution.exit_code -ne 0) {
    Write-AlphaResult -State "boinc_v1_alpha_215_workunit_a_failed" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution
    throw "Codex execution failed with exit code $($execution.exit_code)."
  }
  $changed = @(Get-SkybridgeChangedFiles)
  if ($changed.Count -eq 0) {
    Write-AlphaResult -State "boinc_v1_alpha_215_workunit_a_no_change" -Gate $gate -PrUrl $null -ChangedFiles @() -Execution $execution
    throw "No changes produced."
  }
  Assert-SkybridgeAllowedPrPaths -Paths $changed | Out-Null
  $bad = @($changed | Where-Object { $_ -ne $TargetA })
  if ($bad.Count -gt 0) {
    Write-AlphaResult -State "boinc_v1_alpha_215_disallowed_change" -Gate $gate -PrUrl $null -ChangedFiles $changed -Execution $execution
    throw "Unexpected changed file for Workunit A: $($bad -join ', ')"
  }
  git add -- $TargetA
  git commit -m "BOINC v1 Alpha 215 Workunit A" | Out-Null
  git push -u origin $TaskBranch | Out-Null
  $body = New-TaskPrBody -ChangedFiles $changed -Gate $gate
  $bodyPath = Resolve-AlphaPath "$EvidenceDir/workunit-a-pr-body.md"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bodyPath) | Out-Null
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding utf8
  $prUrl = (gh pr create --title "BOINC v1 Alpha 215 Workunit A: $WorkunitAId" --body-file $bodyPath --base main --head $TaskBranch | Out-String).Trim()
  $hold = Write-AlphaResult -State "held_waiting_human_pr_review_workunit_a" -Gate $gate -PrUrl $prUrl -ChangedFiles $changed -Execution $execution
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_apply_result.v1"
    alpha_id = $AlphaId
    workunit_a_id = $WorkunitAId
    workunit_b_id = $WorkunitBId
    state = "held_waiting_human_pr_review_workunit_a"
    pr_url = $prUrl
    changed_files = $changed
    codex_execution_count = 1
    hold_report = $hold
    token_printed = $false
  }
}

function New-SafeSummary {
  $gate = New-AlphaApplyGate
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_alpha_safe_summary.v1"
    alpha_id = $AlphaId
    workunit_a_id = $WorkunitAId
    workunit_b_id = $WorkunitBId
    can_apply_workunit_a = $gate.can_apply_workunit_a
    workunit_b_blocked = $true
    general_apply_enabled = $false
    token_printed = $false
  }
}

$result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_status.v1"; alpha_id = $AlphaId; preview = New-AlphaPreview; apply_gate = New-AlphaApplyGate; token_printed = $false } }
  "alpha-preview" { New-AlphaPreview }
  "alpha-apply-gate" { New-AlphaApplyGate }
  "alpha-workunit-a-preview" { New-AlphaWorkunit -Which A }
  "alpha-workunit-b-preview" { New-AlphaWorkunit -Which B }
  "alpha-workunit-a-apply" { Invoke-WorkunitAApply }
  "alpha-safe-summary" { New-SafeSummary }
  "alpha-report" { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_report.v1"; alpha_id = $AlphaId; preview = New-AlphaPreview; gate = New-AlphaApplyGate; token_printed = $false } }
  "alpha-hold-report" {
    $path = "$EvidenceDir/alpha-hold-report.json"
    $existing = Read-AlphaSafeJson -Path $path
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_hold_report.v1"; alpha_id = $AlphaId; workunit_a_state = "not_started"; workunit_b_state = "blocked_by_unfinalized_workunit_a"; no_next_execution_authorized = $true; token_printed = $false } }
  }
  "evidence" { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_evidence_paths.v1"; alpha_id = $AlphaId; evidence_dir = $EvidenceDir; result_path = "$EvidenceDir/workunit-a-result.json"; evidence_path = "$EvidenceDir/workunit-a-evidence.json"; hold_report_path = "$EvidenceDir/alpha-hold-report.json"; token_printed = $false } }
  "blocked-state" { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_blocked_state.v1"; alpha_id = $AlphaId; workunit_b_state = "blocked_by_unfinalized_workunit_a"; workunit_b_apply_enabled = $false; general_apply_enabled = $false; token_printed = $false } }
  "workunit-a-finalizer-preview" { New-WorkunitAFinalizerPreview }
  "workunit-a-finalizer-apply" { Invoke-WorkunitAFinalizerApply }
  "workunit-a-finalizer-evidence" {
    $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-finalizer-evidence.json"
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_workunit_a_finalizer_evidence.v1"; alpha_id = $AlphaId; exists = $false; token_printed = $false } }
  }
  "workunit-a-finalizer-report" {
    $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-a-finalizer-report.json"
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_workunit_a_finalizer_report.v1"; alpha_id = $AlphaId; workunit_a_completed = $false; token_printed = $false } }
  }
  "workunit-b-apply-gate" { New-WorkunitBApplyGate }
  "workunit-b-apply" { Invoke-WorkunitBApply }
  "workunit-b-hold-report" {
    $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-hold-report.json"
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_workunit_b_hold_report.v1"; alpha_id = $AlphaId; workunit_b_state = "not_executed"; no_next_execution_authorized = $true; token_printed = $false } }
  }
  "workunit-b-finalizer-preview" { New-WorkunitBFinalizerPreview }
  "workunit-b-finalizer-apply" { Invoke-WorkunitBFinalizerApply }
  "workunit-b-finalizer-evidence" {
    $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-finalizer-evidence.json"
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_workunit_b_finalizer_evidence.v1"; alpha_id = $AlphaId; exists = $false; token_printed = $false } }
  }
  "workunit-b-finalizer-report" {
    $existing = Read-AlphaSafeJson -Path "$EvidenceDir/workunit-b-finalizer-report.json"
    if ($existing) { $existing } else { [pscustomobject]@{ schema = "skybridge.boinc_v1_alpha_workunit_b_finalizer_report.v1"; alpha_id = $AlphaId; workunit_b_completed = $false; token_printed = $false } }
  }
  "alpha-completion-readiness" { New-AlphaCompletionReadiness }
}

ConvertTo-JsonOut $result
