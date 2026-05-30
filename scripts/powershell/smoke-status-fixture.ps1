[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("task-limit", "recent-tasks", "active-only", "task-status-filter", "worker-filter", "recovered-filter", "task-detail-event-limit", "json-output", "header-format", "summary-format", "active-only-empty", "summary-counts", "proposal-summary", "show-proposals", "approved-only", "pending-review-only", "color-auto", "color-never-json-clean", "color-task-states", "lease-expiry-detection", "lease-stale-active-task", "lease-release-stale-dry-run", "lease-recovery-requires-apply", "task-stale-claim-detection", "task-stale-running-detection", "task-missing-lease-detection", "task-pr-merged-needs-evidence", "proposal-derived-executed-status", "proposal-converted-unexecuted-count", "proposal-approved-unconverted-count", "proposal-reconciliation", "hygiene-audit", "hygiene-report-json", "hygiene-recover-lease-dry-run", "hygiene-requires-apply")]
  [string]$Scenario,
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; return } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Invoke-StatusJson {
  param([string[]]$Arguments, [string]$Project = "status-filter-project")
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId $Project -Json @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 failed for $Scenario." }
  return ($output | ConvertFrom-Json)
}

function Invoke-StatusText {
  param([string[]]$Arguments, [string]$Project = "status-filter-project")
  $effectiveArgs = @($Arguments)
  if ($effectiveArgs -notcontains "-Color" -and $effectiveArgs -notcontains "-ColorMode") { $effectiveArgs += "-NoColor" }
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId $Project @effectiveArgs
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 failed for $Scenario." }
  return ($output -join "`n")
}

function Invoke-HygieneJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 @Arguments -ApiBase $ApiBase -ProjectId "status-filter-project" -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-hygiene.ps1 failed for $Scenario." }
  return ($output | ConvertFrom-Json)
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-status-fixture-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-status.sqlite"
$jsonFile = Join-Path $tempDir "status-output.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "status-filter-project"; name = "Status Filter Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "status-empty-project"; name = "Status Empty Project" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/status-empty-project/control" @{ state = "paused"; stop_requested = $false; stop_reason = "status_empty_fixture" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/status-filter-project/control" @{ state = "paused"; stop_requested = $false; stop_reason = "status_filter_fixture" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-a"; name = "Status Worker A" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-a/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-b"; name = "Status Worker B" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-b/heartbeat" @{ status_note = "ready" } | Out-Null

  foreach ($task in @(
    @{ task_id = "status-filter-queued"; project_id = "status-filter-project"; title = "Queued"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-running"; project_id = "status-filter-project"; title = "Running"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-claimed"; project_id = "status-filter-project"; title = "Claimed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-completed"; project_id = "status-filter-project"; title = "Completed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-failed"; project_id = "status-filter-project"; title = "Failed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-recovered"; project_id = "status-filter-project"; title = "Recovered"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-blocked"; project_id = "status-filter-project"; title = "Blocked"; risk = "low"; source = "manual" }
  )) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" $task | Out-Null
  }

  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-running/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-running/start" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-claimed/claim" @{ worker_id = "status-worker-b" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-completed/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-completed/complete" @{ worker_id = "status-worker-a"; summary = "done" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-failed/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-failed/fail" @{ worker_id = "status-worker-a"; error_summary = "fixture failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/claim" @{ worker_id = "status-worker-b" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/fail" @{ worker_id = "status-worker-b"; error_summary = "fixture transient failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/evidence-repair" @{
    worker_id = "status-worker-b"
    summary = "Recovered after rerun"
    evidence_summary = @{
      task_id = "status-filter-recovered"
      pr_url = "https://github.com/example/repo/pull/2"
      validation_status = "passed"
      ci_status = "passed_after_rerun"
      risk_status = "low"
      recovered = $true
      summary = "Recovered fixture"
    }
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-blocked/block" @{ error_summary = "fixture block" } | Out-Null

  foreach ($task in @(
    @{ task_id = "status-stale-claim"; project_id = "status-filter-project"; title = "Stale claim"; risk = "low"; source = "manual" },
    @{ task_id = "status-stale-running"; project_id = "status-filter-project"; title = "Stale running"; risk = "low"; source = "manual" },
    @{ task_id = "status-missing-lease"; project_id = "status-filter-project"; title = "Missing lease"; risk = "low"; source = "manual" },
    @{ task_id = "status-pr-needs-evidence"; project_id = "status-filter-project"; title = "PR merged needs evidence"; risk = "low"; source = "manual" }
  )) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" $task | Out-Null
  }
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-stale-claim/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-stale-running/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-stale-running/start" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-missing-lease/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-pr-needs-evidence/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-pr-needs-evidence/fail" @{ worker_id = "status-worker-a"; error_summary = "needs evidence"; pr_url = "https://github.com/example/repo/pull/99" } | Out-Null

  $mutateScript = Join-Path $tempDir "mutate-status-fixture.mjs"
  Set-Content -LiteralPath $mutateScript -Encoding UTF8 -Value @"
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
const old = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
function updateTask(id, mutate) {
  const row = db.prepare('SELECT task_json FROM tasks WHERE task_id = ?').get(id);
  if (!row) throw new Error('missing task ' + id);
  const task = JSON.parse(row.task_json);
  mutate(task);
  db.prepare('UPDATE tasks SET status = ?, assigned_worker_id = ?, updated_at = ?, task_json = ? WHERE task_id = ?').run(
    task.status, task.assigned_worker_id ?? null, task.updated_at, JSON.stringify(task), id
  );
}
updateTask('status-stale-claim', (task) => {
  task.updated_at = old;
  task.lease.lease_expires_at = old;
  task.lease.heartbeat_at = old;
});
updateTask('status-stale-running', (task) => {
  task.updated_at = old;
  task.lease.lease_expires_at = old;
  task.lease.heartbeat_at = old;
});
updateTask('status-missing-lease', (task) => {
  task.updated_at = old;
  delete task.lease;
});
"@
  node $mutateScript $dbFile

  Invoke-SkyBridgeJson "POST" "/v1/master-goals" @{
    master_goal_id = "status-proposal-master"
    project_id = "status-filter-project"
    title = "Status Proposal Master"
    source = "fixture"
    priority = "normal"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/planning-sessions" @{
    planning_session_id = "status-proposal-session"
    master_goal_id = "status-proposal-master"
    project_id = "status-filter-project"
    planner_adapter = @{
      provider = "fixture"
      planner_mode = "fixture"
      prompt_version = "v1"
      input_state_hash = "fixture"
      raw_response_included = $false
      secrets_included = $false
    }
    proposals = @(
      @{
        proposal_id = "prop_status_proposed"
        title = "Proposed docs update"
        dedupe_key = "prop-status-proposed"
        risk = "low"
        task_type = "docs"
        status = "proposed"
        review_status = "proposed"
        policy_decision = "accepted_for_preview"
        expected_files = @("docs/dev/PROPOSAL_REVIEW_QUEUE.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("smoke")
        required_capabilities = @("codex", "git", "gh")
        normalized_required_capabilities = @("codex", "git", "gh")
      },
      @{
        proposal_id = "prop_status_approved"
        title = "Approved docs update"
        dedupe_key = "prop-status-approved"
        risk = "low"
        task_type = "docs"
        status = "approved"
        review_status = "approved"
        policy_decision = "accepted_for_execution"
        expected_files = @("docs/dev/PROGRESS.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("smoke")
        required_capabilities = @("codex", "git", "gh")
        normalized_required_capabilities = @("codex", "git", "gh")
      },
      @{
        proposal_id = "prop_status_rejected"
        title = "Rejected unsafe update"
        dedupe_key = "prop-status-rejected"
        risk = "high"
        task_type = "deploy"
        status = "rejected"
        review_status = "rejected"
        policy_decision = "rejected_high_risk"
        expected_files = @("deploy/unsafe.md")
        acceptance_criteria = @("blocked")
        evidence_requirements = @("blocked")
        required_capabilities = @("codex")
      },
      @{
        proposal_id = "prop_status_converted_executed"
        title = "Converted completed docs update"
        dedupe_key = "prop-status-converted-executed"
        risk = "low"
        task_type = "docs"
        status = "converted"
        review_status = "converted"
        policy_decision = "accepted_for_execution"
        expected_files = @("docs/dev/PROGRESS.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("smoke")
        required_capabilities = @("codex", "git", "gh")
        normalized_required_capabilities = @("codex", "git", "gh")
        converted_task_id = "status-filter-completed"
      },
      @{
        proposal_id = "prop_status_converted_unexecuted"
        title = "Converted running docs update"
        dedupe_key = "prop-status-converted-unexecuted"
        risk = "low"
        task_type = "docs"
        status = "converted"
        review_status = "converted"
        policy_decision = "accepted_for_execution"
        expected_files = @("docs/dev/QUEUE.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("smoke")
        required_capabilities = @("codex", "git", "gh")
        normalized_required_capabilities = @("codex", "git", "gh")
        converted_task_id = "status-filter-running"
      }
    )
  } | Out-Null

  switch ($Scenario) {
    "task-limit" {
      $status = Invoke-StatusJson -Arguments @("-TaskLimit", "2", "-ShowCompleted")
      if (@($status.tasks).Count -ne 2) { throw "Expected exactly two shown tasks." }
      if ($status.filters.truncated -ne $true) { throw "Expected truncated=true." }
    }
    "recent-tasks" {
      $status = Invoke-StatusJson -Arguments @("-RecentTasks", "3", "-ShowCompleted")
      if (@($status.tasks).Count -ne 3) { throw "Expected exactly three recent tasks." }
      if ($status.filters.recent_tasks -ne 3) { throw "Expected recent_tasks=3." }
    }
    "active-only" {
      $status = Invoke-StatusJson -Arguments @("-ActiveOnly")
      if (@($status.tasks).Count -lt 3) { throw "Expected queued, claimed and running tasks." }
      foreach ($task in @($status.tasks)) {
        if ($task.raw_status -notin @("queued", "claimed", "running")) { throw "ActiveOnly returned $($task.raw_status)." }
      }
      if ($status.task_summary.active -lt 3) { throw "Expected active summary count." }
    }
    "task-status-filter" {
      $status = Invoke-StatusJson -Arguments @("-TaskStatus", "failed", "-ExcludeRecovered", "-ShowAll")
      if (@($status.tasks).Count -ne 1) { throw "Expected only one unrecovered failed task." }
      if (@($status.tasks)[0].task_id -ne "status-filter-failed") { throw "Expected unrecovered failed task." }
    }
    "worker-filter" {
      $status = Invoke-StatusJson -Arguments @("-WorkerId", "status-worker-a", "-ShowAll")
      if (@($status.workers).Count -ne 1 -or @($status.workers)[0].worker_id -ne "status-worker-a") { throw "Expected selected worker only." }
      foreach ($task in @($status.tasks)) {
        if ($task.worker_id -ne "status-worker-a") { throw "Worker filter returned task assigned to $($task.worker_id)." }
      }
    }
    "recovered-filter" {
      $status = Invoke-StatusJson -Arguments @("-RecoveredOnly", "-TaskLimit", "20")
      if (@($status.tasks).Count -ne 1) { throw "Expected exactly one recovered task." }
      if (@($status.tasks)[0].display_status -ne "recovered") { throw "Expected recovered display status." }
    }
    "task-detail-event-limit" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-filter-recovered", "-EventLimit", "2")
      if (@($status.tasks).Count -ne 1) { throw "Expected one task detail." }
      $task = @($status.tasks)[0]
      if (@($task.events).Count -gt 2) { throw "Expected events to respect EventLimit." }
      if ($task.event_count -lt 2) { throw "Expected fixture to have multiple events." }
    }
    "json-output" {
      $status = Invoke-StatusJson -Arguments @("-TaskLimit", "3", "-OutputFile", $jsonFile)
      if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) { throw "Expected output file." }
      $fileStatus = Get-Content -Raw -LiteralPath $jsonFile | ConvertFrom-Json
      if ($fileStatus.token_printed -ne $false -or $status.token_printed -ne $false) { throw "Expected token_printed=false." }
      if (@($fileStatus.tasks).Count -ne @($status.tasks).Count) { throw "Expected JSON output file to match stdout shape." }
    }
    "header-format" {
      $text = Invoke-StatusText -Arguments @("-TaskLimit", "1")
      if ($text -notmatch "(?m)^SkyBridge$" -or $text -notmatch "(?m)^  API:" -or $text -notmatch "(?m)^  StopReq:") { throw "Expected grouped header." }
      $status = Invoke-StatusJson -Arguments @("-TaskLimit", "1")
      if (-not $status.display_header -or -not $status.control_summary) { throw "Expected display_header and control_summary JSON." }
    }
    "summary-format" {
      $text = Invoke-StatusText -Arguments @("-TaskLimit", "2", "-ShowCompleted")
      if ($text -notmatch "Task Summary:" -or $text -notmatch "Active:" -or $text -notmatch "Outcomes:" -or $text -notmatch "Display:") { throw "Expected grouped task summary." }
    }
    "active-only-empty" {
      $status = Invoke-StatusJson -Arguments @("-ActiveOnly") -Project "status-empty-project"
      if ($status.task_summary.matching -ne 0 -or $status.task_summary.shown -ne 0) { throw "Expected empty ActiveOnly matching=0 shown=0; got matching=$($status.task_summary.matching) shown=$($status.task_summary.shown) total=$($status.task_summary.total)." }
      $text = Invoke-StatusText -Arguments @("-ActiveOnly") -Project "status-empty-project"
      if ($text -notmatch "Tasks:\s+none") { throw "Expected Tasks: none." }
    }
    "summary-counts" {
      $status = Invoke-StatusJson -Arguments @("-ActiveOnly")
      if ($status.task_summary.total -ne 11) { throw "Expected total task count 11." }
      if ($status.task_summary.matching -ne 6 -or $status.task_summary.shown -ne 6) { throw "Expected six active matching and shown tasks." }
      if ($status.task_summary.truncated -ne $false) { throw "Expected ActiveOnly not truncated." }
    }
    "proposal-summary" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-SummaryOnly")
      if (-not $status.proposal_summary) { throw "Expected proposal summary." }
      if ($status.proposal_summary.proposed -ne 1 -or $status.proposal_summary.approved -ne 1 -or $status.proposal_summary.rejected -ne 1) { throw "Expected proposal lifecycle counts." }
    }
    "show-proposals" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ProposalLimit", "2")
      if (@($status.proposals).Count -ne 2) { throw "Expected proposal limit to apply." }
    }
    "approved-only" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ApprovedOnly")
      if (@($status.proposals).Count -ne 1 -or @($status.proposals)[0].proposal_id -ne "prop_status_approved") { throw "Expected only approved proposal." }
    }
    "pending-review-only" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-PendingReviewOnly")
      if (@($status.proposals).Count -ne 1 -or @($status.proposals)[0].proposal_id -ne "prop_status_proposed") { throw "Expected only pending proposal." }
    }
    "color-auto" {
      $text = Invoke-StatusText -Arguments @("-TaskLimit", "1", "-ColorMode", "Always")
      if ($text -notmatch "`e\[") { throw "Expected ANSI color in always mode." }
    }
    "color-never-json-clean" {
      $statusJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-filter-project" -Json -ColorMode Always
      if ($statusJson -match "`e\[") { throw "JSON output must not contain ANSI color." }
      $text = Invoke-StatusText -Arguments @("-TaskLimit", "1", "-ColorMode", "Never")
      if ($text -match "`e\[") { throw "Never color mode emitted ANSI color." }
    }
    "color-task-states" {
      $text = Invoke-StatusText -Arguments @("-TaskStatus", "failed", "-ExcludeRecovered", "-ShowAll", "-ColorMode", "Always")
      if ($text -notmatch "`e\[31m") { throw "Expected failed task color." }
    }
    "lease-expiry-detection" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim", "-ShowLeases")
      $task = @($status.tasks)[0]
      if ($task.lease_display_status -ne "expired") { throw "Expected expired lease display status; got $($task.lease_display_status)." }
    }
    "lease-stale-active-task" {
      $status = Invoke-StatusJson -Arguments @("-Hygiene", "-ShowLeases", "-ShowAll")
      if ($status.hygiene_summary.stale_leases -lt 1) { throw "Expected stale lease count." }
    }
    "lease-release-stale-dry-run" {
      $result = Invoke-HygieneJson -Arguments @("recover-lease", "-TaskId", "status-stale-claim", "-LeaseId", "lease-noop", "-Reason", "fixture dry run")
      if ($result.mode -ne "dry-run" -or $result.action -ne "would_release_stale_lease") { throw "Expected dry-run lease release." }
    }
    "lease-recovery-requires-apply" {
      $before = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim", "-ShowLeases")
      $result = Invoke-HygieneJson -Arguments @("recover-lease", "-TaskId", "status-stale-claim", "-Reason", "fixture requires apply")
      $after = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim", "-ShowLeases")
      if ($result.mode -ne "dry-run" -or @($after.tasks)[0].lease_status -ne @($before.tasks)[0].lease_status) { throw "Expected no mutation without -Apply." }
    }
    "task-stale-claim-detection" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim")
      if (@($status.tasks)[0].task_hygiene_status -ne "stale_claim") { throw "Expected stale_claim." }
    }
    "task-stale-running-detection" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-running")
      if (@($status.tasks)[0].task_hygiene_status -ne "stale_running") { throw "Expected stale_running." }
    }
    "task-missing-lease-detection" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-missing-lease")
      if (@($status.tasks)[0].task_hygiene_status -ne "lease_missing") { throw "Expected lease_missing." }
    }
    "task-pr-merged-needs-evidence" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-pr-needs-evidence")
      if (@($status.tasks)[0].task_hygiene_status -ne "pr_merged_needs_evidence") { throw "Expected pr_merged_needs_evidence." }
    }
    "proposal-derived-executed-status" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ReconcileProposals", "-ShowAll")
      $proposal = @($status.proposals | Where-Object { $_.proposal_id -eq "prop_status_converted_executed" })[0]
      if ($proposal.derived_execution_status -ne "executed") { throw "Expected derived executed proposal." }
    }
    "proposal-converted-unexecuted-count" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ReconcileProposals", "-SummaryOnly")
      if ($status.proposal_summary.converted_unexecuted -lt 1) { throw "Expected converted_unexecuted count." }
    }
    "proposal-approved-unconverted-count" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ReconcileProposals", "-SummaryOnly")
      if ($status.proposal_summary.approved_unconverted -ne 1) { throw "Expected one approved_unconverted proposal." }
    }
    "proposal-reconciliation" {
      $status = Invoke-StatusJson -Arguments @("-ShowProposals", "-ReconcileProposals", "-SummaryOnly")
      if ($status.proposal_summary.derived_executed -lt 1 -or $status.proposal_summary.converted_unexecuted -lt 1) { throw "Expected proposal reconciliation summary." }
    }
    "hygiene-audit" {
      $status = Invoke-StatusJson -Arguments @("-Hygiene", "-ShowProposals", "-ShowLeases", "-ShowAll")
      if (-not $status.hygiene_summary -or @($status.hygiene_findings).Count -lt 1) { throw "Expected hygiene summary and findings." }
    }
    "hygiene-report-json" {
      $result = Invoke-HygieneJson -Arguments @("audit")
      if (-not $result.hygiene_summary -or $result.token_printed -ne $false) { throw "Expected hygiene JSON audit." }
    }
    "hygiene-recover-lease-dry-run" {
      $result = Invoke-HygieneJson -Arguments @("recover-lease", "-TaskId", "status-stale-claim", "-Reason", "fixture dry run")
      if ($result.action -ne "would_release_stale_lease") { throw "Expected recover lease dry-run action." }
    }
    "hygiene-requires-apply" {
      $before = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim", "-ShowLeases")
      Invoke-HygieneJson -Arguments @("mark-abandoned", "-TaskId", "status-stale-claim", "-Reason", "fixture apply guard") | Out-Null
      $after = Invoke-StatusJson -Arguments @("-TaskId", "status-stale-claim", "-ShowLeases")
      if (@($after.tasks)[0].lease_status -ne @($before.tasks)[0].lease_status) { throw "Expected no mark-abandoned mutation without -Apply." }
    }
  }

  $summary = [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    api_base = $ApiBase
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
