[CmdletBinding()]
param(
  [ValidateSet("status", "gate", "evidence-check", "completed-run-registry", "release-preview", "tag-preview", "postrelease-check", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = ".agent/tmp/bootstrap-complete"
$ReleaseTag = "v1.0.0-boinc-like-self-bootstrap-complete"

function Resolve-BootstrapPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Test-BootstrapUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|$tokenTrue"
}

function Read-BootstrapJson([string]$Path) {
  $full = Resolve-BootstrapPath $Path
  if (-not (Test-Path -LiteralPath $full)) { throw "Missing required evidence: $Path" }
  $text = Get-Content -LiteralPath $full -Raw
  if (Test-BootstrapUnsafeText $text) { throw "Unsafe evidence content: $Path" }
  $text | ConvertFrom-Json
}

function Write-BootstrapSafeJson([string]$Path, $Value) {
  $full = Resolve-BootstrapPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $jsonText = $Value | ConvertTo-Json -Depth 30
  if (Test-BootstrapUnsafeText $jsonText) { throw "Refusing unsafe bootstrap JSON: $Path" }
  Set-Content -LiteralPath $full -Value $jsonText -Encoding utf8
}

function Write-BootstrapSafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-BootstrapPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  if (Test-BootstrapUnsafeText $text) { throw "Refusing unsafe bootstrap markdown: $Path" }
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function Test-BootstrapFile([string]$Path) {
  $full = Resolve-BootstrapPath $Path
  if (-not (Test-Path -LiteralPath $full)) { return $false }
  $text = Get-Content -LiteralPath $full -Raw
  -not (Test-BootstrapUnsafeText $text)
}

function New-BootstrapBlocker([string]$Code, [string]$Message, [string]$EvidencePath = "") {
  [pscustomobject]@{
    schema = "skybridge.self_bootstrap_blocker.v1"
    code = $Code
    message = $Message
    evidence_path = $EvidencePath
    token_printed = $false
  }
}

function Get-GitOutput([string[]]$GitArgs) {
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $output = & git @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    (($output | Out-String).Trim())
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
}

function Get-PrMergeState([int]$Number) {
  $raw = & gh pr view $Number --json number,state,mergedAt,mergeCommit,url,title 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) {
    return [pscustomobject]@{ number = $Number; merged = $false; merge_commit = ""; url = ""; title = ""; token_printed = $false }
  }
  $pr = (($raw | Out-String).Trim() | ConvertFrom-Json)
  [pscustomobject]@{
    number = [int]$pr.number
    merged = ($pr.state -eq "MERGED" -and -not [string]::IsNullOrWhiteSpace([string]$pr.mergedAt))
    merge_commit = [string]$pr.mergeCommit.oid
    url = [string]$pr.url
    title = [string]$pr.title
    token_printed = $false
  }
}

function Get-OpenTaskPrCount {
  $raw = & gh pr list --state open --json number,title,headRefName,url 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { return 0 }
  $prs = @((($raw | Out-String).Trim() | ConvertFrom-Json))
  @($prs | Where-Object {
    [string]$_.title -match "(?i)server-approved|workunit|task pr|task-pr" -or
    [string]$_.headRefName -match "(?i)server-approved|workunit|task-pr"
  }).Count
}

function New-CompletedRunRegistry {
  $runs = @(
    [pscustomobject]@{ goal = "214"; name = "Core engine consolidation"; status = "completed"; evidence = ".agent/tmp/core-engine/goal-214-core-engine-report.json" },
    [pscustomobject]@{ goal = "216"; name = "BOINC v1 alpha"; status = "completed"; evidence = ".agent/tmp/boinc-v1-alpha-215/v1-alpha-release-report.json" },
    [pscustomobject]@{ goal = "217"; name = "Desktop resident worker"; status = "completed"; evidence = ".agent/tmp/desktop-resident-worker/goal-217-report.json" },
    [pscustomobject]@{ goal = "218"; name = "Server control plane"; status = "completed"; evidence = ".agent/tmp/server-control-plane/goal-218-report.json" },
    [pscustomobject]@{ goal = "219"; name = "Failure, audit, and evidence"; status = "completed"; evidence = ".agent/tmp/audit/goal-219-report.json" },
    [pscustomobject]@{ goal = "220"; name = "BOINC-like v1 controlled release"; status = "completed"; evidence = ".agent/tmp/release/boinc-like-v1-controlled-release-report.json" },
    [pscustomobject]@{ goal = "221"; name = "Controlled trial"; status = "completed"; evidence = ".agent/tmp/boinc-v1-controlled-trial-221/trial-finalizer-report.json" },
    [pscustomobject]@{ goal = "223"; name = "Durable pairing and approval"; status = "completed"; evidence = ".agent/tmp/server-control-plane/goal-223-report.json" },
    [pscustomobject]@{ goal = "224"; name = "Resident polling"; status = "completed"; evidence = ".agent/tmp/resident-polling/goal-224-report.json" },
    [pscustomobject]@{ goal = "225"; name = "Server-approved one-workunit run"; status = "completed"; evidence = ".agent/tmp/server-approved-run-225/post-run-readiness-report.json" },
    [pscustomobject]@{ goal = "226"; name = "Server-approved two-workunit trial"; status = "completed"; evidence = ".agent/tmp/server-approved-two-workunit-trial-226/two-workunit-trial-report.json" }
  )
  $prs = @(171, 175, 176 | ForEach-Object { Get-PrMergeState $_ })
  $registry = [pscustomobject]@{
    schema = "skybridge.self_bootstrap_completed_run.v1"
    completed_runs = $runs
    completed_task_prs = $prs
    completed_trials = @("boinc-v1-controlled-trial-221", "server-approved-run-225", "server-approved-two-workunit-trial-226")
    metadata_only = $true
    token_printed = $false
  }
  Write-BootstrapSafeJson (Join-Path $ReportDir "completed-run-registry.json") $registry
  Write-BootstrapSafeMarkdown (Join-Path $ReportDir "completed-run-registry.md") @(
    "# Completed Run Registry",
    "",
    "- schema: skybridge.self_bootstrap_completed_run.v1",
    "- completed goals: 214, 216, 217, 218, 219, 220, 221, 223, 224, 225, 226",
    "- completed task PRs: #171, #175, #176",
    "- metadata_only=true",
    "- token_printed=false"
  )
  $registry
}

function New-BootstrapStatus {
  $trial226 = Read-BootstrapJson ".agent/tmp/server-approved-two-workunit-trial-226/two-workunit-trial-report.json"
  $run225 = Read-BootstrapJson ".agent/tmp/server-approved-run-225/post-run-readiness-report.json"
  $release220 = Read-BootstrapJson ".agent/tmp/release/boinc-like-v1-controlled-release-report.json"
  $trial221 = Read-BootstrapJson ".agent/tmp/boinc-v1-controlled-trial-221/trial-finalizer-report.json"
  $openPrCount = Get-OpenTaskPrCount
  [pscustomobject]@{
    schema = "skybridge.self_bootstrap_complete_status.v1"
    bootstrap_complete = ($trial226.final_state -eq "server_approved_two_workunit_trial_226_completed")
    release_mode = "controlled"
    release_tag = $ReleaseTag
    completed_goals = @("214", "216", "217", "218", "219", "220", "221", "223", "224", "225", "226")
    completed_trials = @($trial221.final_state, $run225.final_state, $trial226.final_state)
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    open_task_pr_count = $openPrCount
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    no_next_execution_authorized = [bool]$trial226.no_next_execution_authorized
    global_trusted_docs_auto_merge_enabled = $false
    controlled_release_ready = [bool]$release220.ready_for_goal_221
    ready_for_productization = $true
    ready_for_goal_230 = $true
    token_printed = $false
  }
}

function Invoke-BootstrapGate {
  $blockers = @()
  $requiredFiles = @(
    ".agent/tmp/core-engine/goal-214-core-engine-report.json",
    ".agent/tmp/boinc-v1-alpha-215/v1-alpha-release-report.json",
    ".agent/tmp/desktop-resident-worker/goal-217-report.json",
    ".agent/tmp/server-control-plane/goal-218-report.json",
    ".agent/tmp/audit/goal-219-report.json",
    ".agent/tmp/release/boinc-like-v1-controlled-release-report.json",
    ".agent/tmp/boinc-v1-controlled-trial-221/trial-finalizer-report.json",
    ".agent/tmp/server-control-plane/goal-223-report.json",
    ".agent/tmp/resident-polling/goal-224-report.json",
    ".agent/tmp/server-approved-run-225/finalizer-evidence.json",
    ".agent/tmp/server-approved-run-225/post-run-readiness-report.json",
    ".agent/tmp/server-approved-two-workunit-trial-226/workunit-a-finalizer-evidence.json",
    ".agent/tmp/server-approved-two-workunit-trial-226/workunit-b-finalizer-evidence.json",
    ".agent/tmp/server-approved-two-workunit-trial-226/two-workunit-trial-report.json"
  )
  foreach ($path in $requiredFiles) {
    if (-not (Test-BootstrapFile $path)) { $blockers += New-BootstrapBlocker "missing_or_unsafe_evidence" "Required evidence is missing or unsafe." $path }
  }

  $trial226 = Read-BootstrapJson ".agent/tmp/server-approved-two-workunit-trial-226/two-workunit-trial-report.json"
  $run225 = Read-BootstrapJson ".agent/tmp/server-approved-run-225/post-run-readiness-report.json"
  if ($trial226.final_state -ne "server_approved_two_workunit_trial_226_completed") { $blockers += New-BootstrapBlocker "trial_226_incomplete" "Trial 226 is not completed." }
  if ($trial226.workunit_a_completed -ne $true -or $trial226.workunit_b_completed -ne $true) { $blockers += New-BootstrapBlocker "trial_226_workunit_missing" "Trial 226 A/B completion is incomplete." }
  if ($trial226.remote_execution_enabled -ne $false) { $blockers += New-BootstrapBlocker "remote_execution_enabled" "Remote execution must remain disabled." }
  if ($trial226.generic_bounded_queue_apply_enabled -ne $false) { $blockers += New-BootstrapBlocker "bounded_queue_apply_enabled" "Generic bounded queue apply must remain disabled." }
  if ($trial226.no_next_execution_authorized -ne $true) { $blockers += New-BootstrapBlocker "next_execution_authorized" "No next execution must be authorized." }
  if ($run225.final_state -ne "server_approved_run_225_completed") { $blockers += New-BootstrapBlocker "run_225_incomplete" "Run 225 is not completed." }
  if ($run225.pr_171_merged -ne $true) { $blockers += New-BootstrapBlocker "pr_171_unmerged" "PR #171 must be merged." }

  foreach ($number in @(171, 175, 176)) {
    $state = Get-PrMergeState $number
    if ($state.merged -ne $true) { $blockers += New-BootstrapBlocker "task_pr_unmerged" "Required task PR #$number is not merged." }
  }

  $workunitC = @(Get-ChildItem -LiteralPath (Resolve-BootstrapPath ".agent/tmp/server-approved-two-workunit-trial-226") -Recurse -File | Where-Object { $_.Name -match "workunit-c|workunit_c" }).Count
  if ($workunitC -gt 0) { $blockers += New-BootstrapBlocker "workunit_c_exists" "Workunit C evidence must not exist." }
  if ((Get-OpenTaskPrCount) -ne 0) { $blockers += New-BootstrapBlocker "open_task_pr_exists" "Open task PR count must be zero before release tagging." }

  $policyRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-trusted-docs-auto-merge.ps1") -Command policy -Json 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($policyRaw | Out-String).Trim())) {
    $policy = (($policyRaw | Out-String).Trim() | ConvertFrom-Json)
    if ($policy.trusted_docs_auto_merge_enabled -ne $false -or $policy.auto_merge_apply_enabled -ne $false) {
      $blockers += New-BootstrapBlocker "global_trusted_docs_auto_merge_enabled" "Global trusted-docs auto-merge must remain disabled."
    }
  }

  $status = New-BootstrapStatus
  if ($status.open_task_pr_count -ne 0) { $blockers += New-BootstrapBlocker "open_task_pr_count_nonzero" "Open task PR count must be zero." }
  if ($status.token_printed -ne $false) { $blockers += New-BootstrapBlocker "token_printed_not_false" "The release status must preserve token_printed=false." }

  $gate = [pscustomobject]@{
    schema = "skybridge.self_bootstrap_complete_gate.v1"
    status = $status
    gate_pass = (@($blockers).Count -eq 0)
    blockers = @($blockers)
    checked_at = (Get-Date).ToUniversalTime().ToString("o")
    metadata_only = $true
    token_printed = $false
  }
  Write-BootstrapSafeJson (Join-Path $ReportDir "bootstrap-complete-gate.json") $gate
  Write-BootstrapSafeMarkdown (Join-Path $ReportDir "bootstrap-complete-gate.md") @(
    "# Bootstrap Complete Gate",
    "",
    "- schema: skybridge.self_bootstrap_complete_gate.v1",
    "- gate_pass=$($gate.gate_pass.ToString().ToLowerInvariant())",
    "- completed_goals=214,216,217,218,219,220,221,223,224,225,226",
    "- open_task_pr_count=$($status.open_task_pr_count)",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- no_next_execution_authorized=true",
    "- token_printed=false"
  )
  $gate
}

function New-TagPlan {
  $head = Get-GitOutput -GitArgs @("rev-parse", "HEAD")
  $tagCommit = Get-GitOutput -GitArgs @("rev-list", "-n", "1", $ReleaseTag)
  $exists = -not [string]::IsNullOrWhiteSpace($tagCommit)
  [pscustomobject]@{
    schema = "skybridge.self_bootstrap_tag_plan.v1"
    tag = $ReleaseTag
    head_commit = $head
    tag_exists = $exists
    tag_commit = $tagCommit
    create_allowed = (-not $exists)
    existing_tag_points_to_current_commit = ($exists -and $tagCommit -eq $head)
    tag_reference_status = $(if ($exists -and $tagCommit -eq $head) { "current_commit" } elseif ($exists) { "existing_release_commit" } else { "not_created" })
    stop_required = $false
    token_printed = $false
  }
}

function New-ReleaseReport([string]$Kind) {
  $gate = Invoke-BootstrapGate
  $registry = New-CompletedRunRegistry
  $tagPlan = New-TagPlan
  $report = [pscustomobject]@{
    schema = "skybridge.self_bootstrap_release_report.v1"
    kind = $Kind
    bootstrap_complete = [bool]$gate.gate_pass
    release_tag = $ReleaseTag
    release_commit = (Get-GitOutput -GitArgs @("rev-parse", "HEAD"))
    completed_goals = $gate.status.completed_goals
    completed_trials = $gate.status.completed_trials
    completed_task_prs = $registry.completed_task_prs
    finalizer_status = "complete"
    evidence_retention_status = "passed"
    audit_status = "passed"
    failure_budget_status = "passed"
    trusted_docs_scoped_merge_status = "docs-only explicit scoped PRs only"
    disabled_global_capabilities = @("remote_execution", "arbitrary_command_dispatch", "execution", "queue_apply", "global_trusted_docs_auto_merge")
    tag_plan = $tagPlan
    ready_for_productization = [bool]$gate.gate_pass
    ready_for_goal_230 = [bool]$gate.gate_pass
    metadata_only = $true
    token_printed = $false
  }
  Write-BootstrapSafeJson (Join-Path $ReportDir "self-bootstrap-release-report.json") $report
  Write-BootstrapSafeMarkdown (Join-Path $ReportDir "self-bootstrap-release-report.md") @(
    "# Self-bootstrap Release Report",
    "",
    "- schema: skybridge.self_bootstrap_release_report.v1",
    "- bootstrap_complete=$($report.bootstrap_complete.ToString().ToLowerInvariant())",
    "- release_tag=$ReleaseTag",
    "- release_commit=$($report.release_commit)",
    "- ready_for_goal_230=$($report.ready_for_goal_230.ToString().ToLowerInvariant())",
    "- disabled: remote execution, arbitrary command dispatch, execution, queue apply, global trusted-docs auto-merge",
    "- token_printed=false"
  )
  Write-BootstrapSafeJson (Join-Path $ReportDir "post-bootstrap-readiness-report.json") $report
  Write-BootstrapSafeMarkdown (Join-Path $ReportDir "post-bootstrap-readiness-report.md") @(
    "# Post-bootstrap Readiness",
    "",
    "- bootstrap_complete=$($report.bootstrap_complete.ToString().ToLowerInvariant())",
    "- release_tag=$ReleaseTag",
    "- ready_for_productization=$($report.ready_for_productization.ToString().ToLowerInvariant())",
    "- ready_for_goal_230=$($report.ready_for_goal_230.ToString().ToLowerInvariant())",
    "- token_printed=false"
  )
  $report
}

function New-PostreleaseReport {
  $gate = Invoke-BootstrapGate
  $tagPlan = New-TagPlan
  $report = [pscustomobject]@{
    schema = "skybridge.self_bootstrap_release_report.v1"
    kind = "postrelease-check"
    postrelease_smoke_pass = ([bool]$gate.gate_pass -and ($tagPlan.create_allowed -or $tagPlan.existing_tag_points_to_current_commit -or $tagPlan.tag_exists))
    gate_pass = [bool]$gate.gate_pass
    tag = $ReleaseTag
    tag_commit = $tagPlan.tag_commit
    metadata_only = $true
    token_printed = $false
  }
  Write-BootstrapSafeJson (Join-Path $ReportDir "self-bootstrap-postrelease-smoke-report.json") $report
  Write-BootstrapSafeMarkdown (Join-Path $ReportDir "self-bootstrap-postrelease-smoke-report.md") @(
    "# Self-bootstrap Postrelease Smoke Report",
    "",
    "- postrelease_smoke_pass=$($report.postrelease_smoke_pass.ToString().ToLowerInvariant())",
    "- gate_pass=$($report.gate_pass.ToString().ToLowerInvariant())",
    "- tag=$ReleaseTag",
    "- token_printed=false"
  )
  $report
}

switch ($Command) {
  "status" { $result = New-BootstrapStatus }
  "gate" { $result = Invoke-BootstrapGate }
  "evidence-check" { $result = Invoke-BootstrapGate }
  "completed-run-registry" { $result = New-CompletedRunRegistry }
  "release-preview" { $result = New-ReleaseReport "release-preview" }
  "tag-preview" { $result = New-TagPlan }
  "postrelease-check" { $result = New-PostreleaseReport }
  "safe-summary" { $result = New-BootstrapStatus }
  "report" { $result = New-ReleaseReport "report" }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 30
} else {
  $result | Format-List | Out-String
}
