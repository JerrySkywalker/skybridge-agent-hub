[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("task-limit", "recent-tasks", "active-only", "task-status-filter", "worker-filter", "recovered-filter", "task-detail-event-limit", "json-output", "header-format", "summary-format", "active-only-empty", "summary-counts", "proposal-summary", "show-proposals", "approved-only", "pending-review-only")]
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
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId $Project @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 failed for $Scenario." }
  return ($output -join "`n")
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
      if ($status.task_summary.total -ne 7) { throw "Expected total task count 7." }
      if ($status.task_summary.matching -ne 3 -or $status.task_summary.shown -ne 3) { throw "Expected three active matching and shown tasks." }
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
