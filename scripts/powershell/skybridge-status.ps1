[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [Alias("TasksLimit")]
  [int]$TaskLimit = 10,
  [int]$RecentTasks = 0,
  [string[]]$TaskStatus = @(),
  [switch]$ActiveOnly,
  [string]$WorkerId,
  [switch]$RecoveredOnly,
  [switch]$IncludeRecovered,
  [switch]$ExcludeRecovered,
  [string]$TaskId,
  [int]$EventLimit = 25,
  [switch]$IncludeEvents,
  [string]$Since,
  [string]$Until,
  [ValidateSet("updated_at", "created_at", "last_event", "status")]
  [string]$SortBy = "updated_at",
  [switch]$Descending,
  [switch]$SummaryOnly,
  [switch]$ShowProposals,
  [int]$ProposalLimit = 10,
  [string[]]$ProposalStatus = @(),
  [string[]]$ReviewStatus = @(),
  [switch]$ApprovedOnly,
  [switch]$PendingReviewOnly,
  [switch]$ShowCampaigns,
  [string]$CampaignId,
  [switch]$ShowCampaignSteps,
  [int]$CampaignLimit = 10,
  [switch]$ShowLeases,
  [switch]$ShowLocks,
  [switch]$Hygiene,
  [switch]$StaleOnly,
  [switch]$BlockedOnly,
  [switch]$FailedOnly,
  [switch]$NeedsReview,
  [switch]$NeedsReconciliation,
  [switch]$ReconcileProposals,
  [int]$WorkersLimit = 12,
  [switch]$ShowCompleted,
  [switch]$ShowAll,
  [switch]$Color,
  [switch]$NoColor,
  [ValidateSet("Auto", "Always", "Never")]
  [string]$ColorMode = "Auto",
  [int]$TimeoutSeconds = 30,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-StatusApiConfig {
  $authMode = "none"
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar) -or -not [string]::IsNullOrWhiteSpace($TokenFile)) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Shorten-StatusText {
  param([string]$Value, [int]$Width)
  if ([string]::IsNullOrWhiteSpace($Value)) { $Value = "-" }
  if ($Value.Length -le $Width) { return $Value.PadRight($Width) }
  if ($Width -le 1) { return $Value.Substring(0, $Width) }
  return ($Value.Substring(0, $Width - 1) + "~")
}

function ConvertTo-StatusDate {
  param($Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
  try {
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) {
      $dt = [datetime]$Value
      if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [datetime]::SpecifyKind($dt, [DateTimeKind]::Utc) }
      return $dt.ToUniversalTime()
    }
    return ([datetimeoffset]::Parse([string]$Value)).UtcDateTime
  } catch {
    return $null
  }
}

function Format-RelativeTime {
  param($TimeValue)
  $seen = ConvertTo-StatusDate -Value $TimeValue
  if (-not $seen) { return "-" }
  $age = [datetime]::UtcNow - $seen
  if ($age.TotalSeconds -lt 90) { return "$([int][Math]::Max(0, $age.TotalSeconds))s ago" }
  if ($age.TotalMinutes -lt 90) { return "$([int]$age.TotalMinutes)m ago" }
  if ($age.TotalHours -lt 48) { return "$([int]$age.TotalHours)h ago" }
  return "$([int]$age.TotalDays)d ago"
}

function Test-StatusColorEnabled {
  if ($Json -or -not [string]::IsNullOrWhiteSpace($OutputFile)) { return $false }
  if ($NoColor -or -not [string]::IsNullOrWhiteSpace($env:NO_COLOR)) { return $false }
  if ($Color -or $ColorMode -eq "Always") { return $true }
  if ($ColorMode -eq "Never") { return $false }
  if ($Host.Name -match "ConsoleHost|Visual Studio Code") { return $true }
  if ($env:WT_SESSION -or $env:TERM_PROGRAM -or ($env:TERM -and $env:TERM -ne "dumb")) { return $true }
  return $false
}

$script:StatusColorEnabled = Test-StatusColorEnabled

function Format-StatusColor {
  param([string]$Text, [string]$ColorName)
  if (-not $script:StatusColorEnabled -or [string]::IsNullOrEmpty($Text)) { return $Text }
  $codes = @{
    red = "31"; green = "32"; yellow = "33"; blue = "34"; cyan = "36"; dim = "2"; bold = "1"
  }
  $code = if ($codes.ContainsKey($ColorName)) { $codes[$ColorName] } else { $null }
  if (-not $code) { return $Text }
  return "$([char]27)[$code" + "m$Text$([char]27)[0m"
}

function Strip-AnsiForTest {
  param([string]$Text)
  return ([regex]::Replace($Text, "`e\[[0-9;]*m", ""))
}

function Get-StatusColorName {
  param([string]$Kind, [string]$Value)
  $valueText = ([string]$Value).Trim().ToLowerInvariant()
  switch ($Kind) {
    "health" { if ($valueText -eq "ok") { return "green" } return "red" }
    "control" { if ($valueText -eq "paused") { return "cyan" } if ($valueText -eq "running") { return "green" } return "yellow" }
    "stop" { if ($valueText -eq "true") { return "yellow" } return "green" }
    "task" {
      if ($valueText -match "failed_unrecovered|failed$") { return "red" }
      if ($valueText -match "blocked|stale|expired|missing") { return "yellow" }
      if ($valueText -match "queued|claimed|running|active") { return "yellow" }
      if ($valueText -match "recovered|completed") { return "green" }
      return "dim"
    }
    "proposal" {
      if ($valueText -match "rejected|high") { return "red" }
      if ($valueText -match "deferred|blocked|proposed|reviewed") { return "yellow" }
      if ($valueText -match "approved|executed") { return "green" }
      if ($valueText -match "converted") { return "cyan" }
      return "dim"
    }
    "lease" {
      if ($valueText -match "stale|expired|abandoned|inconsistent") { return "red" }
      if ($valueText -match "active") { return "yellow" }
      if ($valueText -match "released") { return "green" }
      return "dim"
    }
    "campaign" {
      if ($valueText -match "failed|aborted") { return "red" }
      if ($valueText -match "held|needs_human|blocked") { return "yellow" }
      if ($valueText -match "running|completed|recovered") { return "green" }
      if ($valueText -match "ready|paused") { return "cyan" }
      return "dim"
    }
    default { return "dim" }
  }
}

function Colorize-StatusValue {
  param([string]$Kind, $Value)
  $text = [string]$Value
  return (Format-StatusColor -Text $text -ColorName (Get-StatusColorName -Kind $Kind -Value $text))
}

function Get-LeaseDerivedStatus {
  param($Lease, [string]$TaskStatus, [string]$WorkerStatus)
  if (-not $Lease) { return $null }
  $status = if ($Lease.lease_status) { [string]$Lease.lease_status } else { "active" }
  $expiresAt = ConvertTo-StatusDate -Value $Lease.lease_expires_at
  $isActive = $status -eq "active"
  if ($isActive -and $expiresAt -and $expiresAt -lt [datetime]::UtcNow) { return "expired" }
  if ($isActive -and $TaskStatus -notin @("queued", "claimed", "running")) { return "inconsistent" }
  if ($isActive -and $WorkerStatus -in @("offline", "stale")) { return "stale" }
  return $status
}

function Get-TaskHygieneStatus {
  param($Task, [string]$WorkerStatus)
  $rawStatus = if ($Task.status) { [string]$Task.status } else { "queued" }
  $leaseStatus = Get-LeaseDerivedStatus -Lease $Task.lease -TaskStatus $rawStatus -WorkerStatus $WorkerStatus
  $updatedAt = ConvertTo-StatusDate -Value $Task.updated_at
  $ageMinutes = if ($updatedAt) { ([datetime]::UtcNow - $updatedAt).TotalMinutes } else { 0 }
  $result = $Task.result
  $evidence = if ($result -and $result.evidence_summary) { $result.evidence_summary } else { $null }
  $recovered = $evidence -and $evidence.recovered -eq $true
  $prUrl = if ($result -and $result.pr_url) { [string]$result.pr_url } elseif ($Task.pr_url) { [string]$Task.pr_url } else { $null }
  if ($rawStatus -in @("claimed", "running") -and -not $Task.lease) { return "lease_missing" }
  if ($rawStatus -eq "claimed" -and $ageMinutes -gt 30) { return "stale_claim" }
  if ($rawStatus -eq "running" -and $ageMinutes -gt 60) { return "stale_running" }
  if ($leaseStatus -eq "expired") { return "lease_expired" }
  if ($rawStatus -eq "failed" -and $prUrl -and -not $recovered) { return "pr_merged_needs_evidence" }
  if ($rawStatus -eq "failed" -and $recovered) { return "recovered_ok" }
  if ($rawStatus -eq "blocked") { return "blocked_historical" }
  if ($rawStatus -eq "failed") { return "failed_unrecovered" }
  if ($rawStatus -in @("queued", "claimed", "running")) { return "active_ok" }
  return "ok"
}

function Select-TaskSummary {
  param($Task, [hashtable]$WorkerStatusById = @{})
  $result = $Task.result
  $events = @($Task.events)
  $lastEvent = if ($Task.last_event) { $Task.last_event } elseif ($events.Count -gt 0) { $events[-1] } else { $null }
  $evidenceSummary = if ($result -and $result.evidence_summary) { $result.evidence_summary } else { $null }
  $ciStatus = if ($evidenceSummary -and $evidenceSummary.ci_status) { [string]$evidenceSummary.ci_status } else { $null }
  $recovered = if ($evidenceSummary -and $evidenceSummary.recovered -eq $true) { $true } else { $false }
  $prUrl = if ($result -and $result.pr_url) { [string]$result.pr_url } elseif ($Task.pr_url) { [string]$Task.pr_url } else { $null }
  $rawStatus = if ($Task.status) { [string]$Task.status } else { "queued" }
  $displayStatus = $rawStatus
  if ($rawStatus -eq "failed" -and $recovered) { $displayStatus = if ($ciStatus -eq "passed_after_rerun") { "recovered" } else { "failed/recovered" } }
  $eventRows = if ($IncludeEvents -or $TaskId) { @($events | Select-Object -Last $EventLimit) } else { @() }
  $lease = if ($Task.lease) { $Task.lease } else { $null }
  $workerForTask = if ($Task.assigned_worker_id -and $WorkerStatusById.ContainsKey([string]$Task.assigned_worker_id)) { [string]$WorkerStatusById[[string]$Task.assigned_worker_id] } else { $null }
  $leaseDerivedStatus = Get-LeaseDerivedStatus -Lease $lease -TaskStatus $rawStatus -WorkerStatus $workerForTask
  $hygieneStatus = Get-TaskHygieneStatus -Task $Task -WorkerStatus $workerForTask
  [pscustomobject]@{
    task_id = if ($Task.task_id) { [string]$Task.task_id } else { "-" }
    status = $rawStatus
    raw_status = $rawStatus
    display_status = $displayStatus
    title = if ($Task.title) { [string]$Task.title } else { "-" }
    worker_id = if ($Task.assigned_worker_id) { [string]$Task.assigned_worker_id } else { "-" }
    task_type = if ($Task.task_type) { [string]$Task.task_type } else { $null }
    required_capabilities = @($Task.required_capabilities)
    allowed_paths = @($Task.allowed_paths)
    updated_at = if ($Task.updated_at) { [string]$Task.updated_at } else { $null }
    created_at = if ($Task.created_at) { [string]$Task.created_at } else { $null }
    last_event_at = if ($lastEvent -and $lastEvent.time) { [string]$lastEvent.time } else { $null }
    pr_url = $prUrl
    result_url = if ($Task.result_url) { [string]$Task.result_url } else { $null }
    error_summary = if ($Task.error_summary) { [string]$Task.error_summary } else { $null }
    pr = if ($prUrl) { "pr" } else { "-" }
    evidence_summary = $evidenceSummary
    lease = $lease
    lease_id = if ($lease -and $lease.lease_id) { [string]$lease.lease_id } else { $null }
    lease_status = if ($lease -and $lease.lease_status) { [string]$lease.lease_status } else { $null }
    lease_display_status = $leaseDerivedStatus
    lease_expires_at = if ($lease -and $lease.lease_expires_at) { [string]$lease.lease_expires_at } else { $null }
    lease_worker_id = if ($lease -and $lease.worker_id) { [string]$lease.worker_id } else { $null }
    lease_stale_reason = if ($lease -and $lease.stale_reason) { [string]$lease.stale_reason } else { $null }
    task_hygiene_status = $hygieneStatus
    worker_status = $workerForTask
    recovered = $recovered
    ci_status = $ciStatus
    summary = if ($result -and $result.summary) { [string]$result.summary } elseif ($Task.error_summary) { [string]$Task.error_summary } else { $null }
    evidence = if ($recovered) { "recovered" } elseif ($ciStatus) { $ciStatus } else { "-" }
    event_count = $events.Count
    events = @($eventRows)
  }
}

function Select-WorkerSummary {
  param($Worker)
  $seenAt = if ($Worker.last_seen_at) { $Worker.last_seen_at } else { $null }
  [pscustomobject]@{
    worker_id = if ($Worker.worker_id) { [string]$Worker.worker_id } else { "-" }
    status = if ($Worker.status) { [string]$Worker.status } else { "offline" }
    last_seen_at = if ($seenAt) { [string]$seenAt } else { $null }
    last_seen = if ($Worker.status -eq "online") { "0s ago" } else { Format-RelativeTime -TimeValue $seenAt }
    current_task_id = if ($Worker.current_task_id) { [string]$Worker.current_task_id } else { $null }
    auth_mode = if ($Worker.auth_mode) { [string]$Worker.auth_mode } else { $null }
    api_base = if ($Worker.api_base) { [string]$Worker.api_base } else { $null }
  }
}

function Test-TaskStatusMatch {
  param($Task, [string[]]$Statuses)
  if ($Statuses.Count -eq 0) { return $true }
  foreach ($status in @($Statuses | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })) {
    if ($status -eq "recovered" -and $Task.recovered) { return $true }
    if ($status -eq "failed") {
      if ($Task.raw_status -eq "failed" -and ($IncludeRecovered -or -not $Task.recovered)) { return $true }
    } elseif ($Task.raw_status -eq $status -or $Task.display_status -eq $status) {
      return $true
    }
  }
  return $false
}

function Get-TaskSortValue {
  param($Task)
  switch ($SortBy) {
    "created_at" { return (ConvertTo-StatusDate -Value $Task.created_at) }
    "last_event" { return (ConvertTo-StatusDate -Value $Task.last_event_at) }
    "status" { return [string]$Task.display_status }
    default { return (ConvertTo-StatusDate -Value $Task.updated_at) }
  }
}

function Get-TaskSummaryCounts {
  param([array]$Tasks, [array]$Matching, [array]$Shown, [bool]$Truncated)
  $taskRows = @($Tasks) | Where-Object { $null -ne $_ }
  $matchingRows = @($Matching) | Where-Object { $null -ne $_ }
  $shownRows = @($Shown) | Where-Object { $null -ne $_ }
  [pscustomobject]@{
    active = @($taskRows | Where-Object { $_.raw_status -in @("queued", "claimed", "running") }).Count
    queued = @($taskRows | Where-Object { $_.raw_status -eq "queued" }).Count
    claimed = @($taskRows | Where-Object { $_.raw_status -eq "claimed" }).Count
    running = @($taskRows | Where-Object { $_.raw_status -eq "running" }).Count
    blocked = @($taskRows | Where-Object { $_.raw_status -eq "blocked" }).Count
    failed_unrecovered = @($taskRows | Where-Object { $_.raw_status -eq "failed" -and -not $_.recovered }).Count
    recovered = @($taskRows | Where-Object { $_.recovered }).Count
    completed = @($taskRows | Where-Object { $_.raw_status -eq "completed" }).Count
    active_leases = @($taskRows | Where-Object { $_.lease_display_status -eq "active" }).Count
    stale_leases = @($taskRows | Where-Object { $_.lease_display_status -in @("expired", "stale", "abandoned", "inconsistent") }).Count
    released_leases = @($taskRows | Where-Object { $_.lease_display_status -eq "released" }).Count
    stale_claims = @($taskRows | Where-Object { $_.task_hygiene_status -eq "stale_claim" }).Count
    stale_running = @($taskRows | Where-Object { $_.task_hygiene_status -eq "stale_running" }).Count
    missing_leases = @($taskRows | Where-Object { $_.task_hygiene_status -eq "lease_missing" }).Count
    needs_evidence = @($taskRows | Where-Object { $_.task_hygiene_status -eq "pr_merged_needs_evidence" }).Count
    total = @($taskRows).Count
    matching = @($matchingRows).Count
    shown = @($shownRows).Count
    truncated = $Truncated
    total_shown = @($shownRows).Count
    total_available = @($taskRows).Count
  }
}

function Select-ProposalSummary {
  param($Proposal, [hashtable]$TaskIndex = @{})
  $convertedTaskId = if ($Proposal.converted_task_id) { [string]$Proposal.converted_task_id } else { $null }
  $convertedTask = if ($convertedTaskId -and $TaskIndex.ContainsKey($convertedTaskId)) { $TaskIndex[$convertedTaskId] } else { $null }
  $taskDisplayStatus = if ($convertedTask) { [string]$convertedTask.display_status } else { $null }
  $evidenceStatus = if ($convertedTask) { [string]$convertedTask.evidence } else { $null }
  $derivedExecutionStatus = if ($convertedTask -and ($convertedTask.raw_status -eq "completed" -or $convertedTask.recovered -or $convertedTask.display_status -eq "recovered")) {
    "executed"
  } elseif ($convertedTaskId) {
    "converted_unexecuted"
  } elseif (($Proposal.status -eq "approved") -or ($Proposal.review_status -eq "approved")) {
    "approved_unconverted"
  } else {
    if ($Proposal.review_status) { [string]$Proposal.review_status } elseif ($Proposal.status) { [string]$Proposal.status } else { "proposed" }
  }
  [pscustomobject]@{
    proposal_id = if ($Proposal.proposal_id) { [string]$Proposal.proposal_id } else { "-" }
    master_goal_id = if ($Proposal.master_goal_id) { [string]$Proposal.master_goal_id } else { $null }
    planning_session_id = if ($Proposal.planning_session_id) { [string]$Proposal.planning_session_id } else { $null }
    status = if ($Proposal.status) { [string]$Proposal.status } else { "proposed" }
    policy_decision = if ($Proposal.policy_decision) { [string]$Proposal.policy_decision } else { "-" }
    review_status = if ($Proposal.review_status) { [string]$Proposal.review_status } else { if ($Proposal.status) { [string]$Proposal.status } else { "proposed" } }
    review_reason = if ($Proposal.review_reason) { [string]$Proposal.review_reason } else { $null }
    risk = if ($Proposal.risk) { [string]$Proposal.risk } else { "-" }
    task_type = if ($Proposal.task_type) { [string]$Proposal.task_type } else { "-" }
    title = if ($Proposal.title) { [string]$Proposal.title } else { "-" }
    expected_files = @($Proposal.expected_files)
    original_required_capabilities = @($Proposal.original_required_capabilities)
    normalized_required_capabilities = @($Proposal.normalized_required_capabilities)
    dependencies = @($Proposal.dependencies)
    converted_task_id = $convertedTaskId
    derived_execution_status = $derivedExecutionStatus
    task_display_status = $taskDisplayStatus
    evidence_status = $evidenceStatus
    updated_at = if ($Proposal.updated_at) { [string]$Proposal.updated_at } else { $null }
  }
}

function Get-ProposalSummaryCounts {
  param([array]$Proposals)
  $counts = [ordered]@{
    proposed = 0
    reviewed = 0
    approved = 0
    rejected = 0
    deferred = 0
    superseded = 0
    blocked_dependency = 0
    converted = 0
    executed = 0
    derived_executed = 0
    converted_unexecuted = 0
    approved_unconverted = 0
    total = @($Proposals).Count
  }
  foreach ($proposal in @($Proposals)) {
    $key = if ($proposal.review_status) { [string]$proposal.review_status } else { [string]$proposal.status }
    if ($counts.Contains($key)) { $counts[$key] = [int]$counts[$key] + 1 }
    if ($proposal.derived_execution_status -eq "executed") { $counts.derived_executed = [int]$counts.derived_executed + 1 }
    if ($proposal.derived_execution_status -eq "converted_unexecuted") { $counts.converted_unexecuted = [int]$counts.converted_unexecuted + 1 }
    if ($proposal.derived_execution_status -eq "approved_unconverted") { $counts.approved_unconverted = [int]$counts.approved_unconverted + 1 }
  }
  [pscustomobject]$counts
}

function Get-HygieneReport {
  param([array]$Tasks, [array]$Proposals, [array]$Workers)
  $taskRows = @($Tasks)
  $proposalRows = @($Proposals)
  $findings = New-Object System.Collections.Generic.List[object]
  foreach ($task in $taskRows) {
    if ($task.task_hygiene_status -in @("stale_claim", "stale_running", "lease_missing", "lease_expired", "pr_merged_needs_evidence", "failed_unrecovered", "blocked_historical")) {
      $severity = if ($task.task_hygiene_status -in @("failed_unrecovered", "lease_expired", "stale_running")) { "warning" } else { "info" }
      $findings.Add([pscustomobject]@{
        kind = "task"
        id = $task.task_id
        status = $task.task_hygiene_status
        severity = $severity
        summary = "$($task.task_id) is $($task.task_hygiene_status)"
        recommended_action = if ($task.task_hygiene_status -eq "pr_merged_needs_evidence") { "inspect PR and run bounded evidence reconciliation if safe" } elseif ($task.task_hygiene_status -match "lease") { "inspect lease and recover only with -Apply and reason" } else { "review before mutation" }
      }) | Out-Null
    }
    if ($task.lease_display_status -in @("expired", "stale", "abandoned", "inconsistent")) {
      $findings.Add([pscustomobject]@{
        kind = "lease"
        id = $task.lease_id
        task_id = $task.task_id
        status = $task.lease_display_status
        severity = "warning"
        summary = "$($task.task_id) lease is $($task.lease_display_status)"
        recommended_action = "dry-run recover-lease before applying any lease mutation"
      }) | Out-Null
    }
  }
  foreach ($proposal in $proposalRows) {
    if ($proposal.derived_execution_status -in @("approved_unconverted", "converted_unexecuted")) {
      $findings.Add([pscustomobject]@{
        kind = "proposal"
        id = $proposal.proposal_id
        status = $proposal.derived_execution_status
        severity = "info"
        summary = "$($proposal.proposal_id) is $($proposal.derived_execution_status)"
        recommended_action = "leave queued for operator review or reconcile only with explicit command"
      }) | Out-Null
    }
  }
  $recommended = @(
    "Use skybridge-hygiene.ps1 audit before mutating queue state.",
    "Use -Apply and -Reason for any lease or task recovery mutation.",
    "Do not unblock task_proposal-59a0236fb69800cd automatically."
  )
  [pscustomobject]@{
    summary = [pscustomobject]@{
      active_tasks = @($taskRows | Where-Object { $_.raw_status -in @("queued", "claimed", "running") }).Count
      stale_claimed_tasks = @($taskRows | Where-Object { $_.task_hygiene_status -eq "stale_claim" }).Count
      stale_running_tasks = @($taskRows | Where-Object { $_.task_hygiene_status -eq "stale_running" }).Count
      blocked_tasks = @($taskRows | Where-Object { $_.raw_status -eq "blocked" }).Count
      failed_unrecovered_tasks = @($taskRows | Where-Object { $_.raw_status -eq "failed" -and -not $_.recovered }).Count
      recovered_tasks = @($taskRows | Where-Object { $_.recovered }).Count
      completed_tasks = @($taskRows | Where-Object { $_.raw_status -eq "completed" }).Count
      active_leases = @($taskRows | Where-Object { $_.lease_display_status -eq "active" }).Count
      stale_leases = @($taskRows | Where-Object { $_.lease_display_status -in @("expired", "stale", "abandoned", "inconsistent") }).Count
      released_leases = @($taskRows | Where-Object { $_.lease_display_status -eq "released" }).Count
      approved_unconverted_proposals = @($proposalRows | Where-Object { $_.derived_execution_status -eq "approved_unconverted" }).Count
      converted_unexecuted_proposals = @($proposalRows | Where-Object { $_.derived_execution_status -eq "converted_unexecuted" }).Count
      derived_executed_proposals = @($proposalRows | Where-Object { $_.derived_execution_status -eq "executed" }).Count
      deferred_proposals = @($proposalRows | Where-Object { $_.review_status -eq "deferred" -or $_.status -eq "deferred" }).Count
      rejected_proposals = @($proposalRows | Where-Object { $_.review_status -eq "rejected" -or $_.status -eq "rejected" }).Count
      old_proposed_proposals = @($proposalRows | Where-Object { $_.review_status -eq "proposed" -or $_.status -eq "proposed" }).Count
      historical_blocked_tasks = @($taskRows | Where-Object { $_.raw_status -eq "blocked" }).Count
    }
    findings = @($findings.ToArray())
    recommended_actions = $recommended
  }
}

function Select-CampaignSummary {
  param($Campaign)
  [pscustomobject]@{
    campaign_id = $Campaign.campaign_id
    project_id = $Campaign.project_id
    title = $Campaign.title
    status = $Campaign.status
    current_step_id = $Campaign.current_step_id
    source = $Campaign.source
    created_at = $Campaign.created_at
    updated_at = $Campaign.updated_at
  }
}

function Select-CampaignStepSummary {
  param($Step)
  $gate = $Step.last_gate_result
  if (-not $gate -and $Step.evidence_summary -and $Step.evidence_summary.gate_result) { $gate = $Step.evidence_summary.gate_result }
  [pscustomobject]@{
    campaign_step_id = $Step.campaign_step_id
    campaign_id = $Step.campaign_id
    goal_id = $Step.goal_id
    title = $Step.title
    order = $Step.order
    status = $Step.status
    dependencies = @($Step.dependencies)
    markdown_path = $Step.markdown_path
    markdown_hash = $Step.markdown_hash
    linked_task_ids = @($Step.linked_task_ids)
    linked_pr_urls = @($Step.linked_pr_urls)
    evidence_summary = $Step.evidence_summary
    last_gate_result = $Step.last_gate_result
    gate_summary = if ($gate) {
      [pscustomobject]@{
        deterministic_decision = $gate.deterministic_decision
        hermes_decision = $gate.hermes_decision
        final_decision = if ($gate.final_decision) { $gate.final_decision } else { $gate.decision }
        human_approval_required = $gate.human_approval_required
        human_approval_present = $gate.human_approval_present
        hard_blockers = @($gate.hard_blockers)
        warnings = @($gate.warnings)
        input_state_hash = $gate.input_state_hash
        prompt_version = $gate.prompt_version
        generated_at = $gate.generated_at
      }
    } else { $null }
    started_at = $Step.started_at
    completed_at = $Step.completed_at
  }
}

function Get-CampaignSummaryCounts {
  param([array]$Campaigns)
  $rows = @($Campaigns)
  [pscustomobject]@{
    total = $rows.Count
    draft = @($rows | Where-Object { $_.status -eq "draft" }).Count
    ready = @($rows | Where-Object { $_.status -eq "ready" }).Count
    running = @($rows | Where-Object { $_.status -eq "running" }).Count
    paused = @($rows | Where-Object { $_.status -eq "paused" }).Count
    held = @($rows | Where-Object { $_.status -eq "held" }).Count
    completed = @($rows | Where-Object { $_.status -eq "completed" }).Count
    failed = @($rows | Where-Object { $_.status -eq "failed" }).Count
    aborted = @($rows | Where-Object { $_.status -eq "aborted" }).Count
  }
}

function Write-CompactStatus {
  param($Status)
  "SkyBridge"
  "  API:      $($Status.api_base)"
  "  Health:   $(Colorize-StatusValue -Kind health -Value $Status.health.status)"
  "  Project:  $($Status.project_id)"
  "  Control:  $(Colorize-StatusValue -Kind control -Value $Status.control.state)"
  "  StopReq:  $(Colorize-StatusValue -Kind stop -Value $Status.control.stop_requested)"
  if ($Status.control.stop_reason) { "  Reason:   $($Status.control.stop_reason)" }
  if ($Status.control.degraded_reason) { "  Degraded: $($Status.control.degraded_reason)" }
  ""
  "Task Summary:"
  "  Active:"
  "    queued:   $(Colorize-StatusValue -Kind task -Value $Status.task_summary.queued)"
  "    claimed:  $(Colorize-StatusValue -Kind task -Value $Status.task_summary.claimed)"
  "    running:  $(Colorize-StatusValue -Kind task -Value $Status.task_summary.running)"
  "    total:    $(Colorize-StatusValue -Kind task -Value $Status.task_summary.active)"
  ""
  "  Outcomes:"
  "    completed:          $(Colorize-StatusValue -Kind task -Value $Status.task_summary.completed)"
  "    recovered:          $(Colorize-StatusValue -Kind task -Value $Status.task_summary.recovered)"
  "    blocked:            $(Colorize-StatusValue -Kind task -Value $Status.task_summary.blocked)"
  "    failed_unrecovered: $(Colorize-StatusValue -Kind task -Value $Status.task_summary.failed_unrecovered)"
  ""
  "  Display:"
  "    total:      $($Status.task_summary.total)"
  "    matching:   $($Status.task_summary.matching)"
  "    shown:      $($Status.task_summary.shown)"
  "    truncated:  $($Status.task_summary.truncated)"
  if ($Status.filters.show_leases) {
    ""
    "  Leases:"
    "    active:   $(Colorize-StatusValue -Kind lease -Value $Status.task_summary.active_leases)"
    "    stale:    $(Colorize-StatusValue -Kind lease -Value $Status.task_summary.stale_leases)"
    "    released: $(Colorize-StatusValue -Kind lease -Value $Status.task_summary.released_leases)"
  }
  "Filters:   $($Status.filters.description)"
  if ($Status.task_summary.truncated) { "Hint:      use -ShowAll or raise -TaskLimit to show more tasks." }
  if ($Status.proposal_summary) {
    ""
    "Proposal Summary:"
    "  proposed:           $($Status.proposal_summary.proposed)"
    "  reviewed:           $($Status.proposal_summary.reviewed)"
    "  approved:           $($Status.proposal_summary.approved)"
    "  rejected:           $($Status.proposal_summary.rejected)"
    "  deferred:           $($Status.proposal_summary.deferred)"
    "  superseded:         $($Status.proposal_summary.superseded)"
    "  blocked_dependency: $($Status.proposal_summary.blocked_dependency)"
    "  converted:          $($Status.proposal_summary.converted)"
    "  executed:           $($Status.proposal_summary.executed)"
    "  derived_executed:   $(Colorize-StatusValue -Kind proposal -Value $Status.proposal_summary.derived_executed)"
    "  approved_unconverted: $($Status.proposal_summary.approved_unconverted)"
    "  converted_unexecuted: $($Status.proposal_summary.converted_unexecuted)"
  }
  if ($Status.hygiene_summary) {
    ""
    "Queue Hygiene:"
    "  active_tasks:                 $(Colorize-StatusValue -Kind task -Value $Status.hygiene_summary.active_tasks)"
    "  stale_claimed_tasks:          $(Colorize-StatusValue -Kind task -Value $Status.hygiene_summary.stale_claimed_tasks)"
    "  stale_running_tasks:          $(Colorize-StatusValue -Kind task -Value $Status.hygiene_summary.stale_running_tasks)"
    "  failed_unrecovered_tasks:     $(Colorize-StatusValue -Kind task -Value $Status.hygiene_summary.failed_unrecovered_tasks)"
    "  stale_leases:                 $(Colorize-StatusValue -Kind lease -Value $Status.hygiene_summary.stale_leases)"
    "  approved_unconverted_props:   $(Colorize-StatusValue -Kind proposal -Value $Status.hygiene_summary.approved_unconverted_proposals)"
    "  converted_unexecuted_props:   $(Colorize-StatusValue -Kind proposal -Value $Status.hygiene_summary.converted_unexecuted_proposals)"
    "  derived_executed_props:       $(Colorize-StatusValue -Kind proposal -Value $Status.hygiene_summary.derived_executed_proposals)"
  }
  if ($Status.campaign_summary) {
    ""
    "Campaign Summary:"
    "  draft:     $($Status.campaign_summary.draft)"
    "  ready:     $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.ready)"
    "  running:   $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.running)"
    "  paused:    $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.paused)"
    "  held:      $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.held)"
    "  completed: $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.completed)"
    "  failed:    $(Colorize-StatusValue -Kind campaign -Value $Status.campaign_summary.failed)"
  }
  if ($Status.campaign_gate_summary) {
    ""
    "Campaign Gate:"
    "  deterministic: $(if ($Status.campaign_gate_summary.deterministic_decision) { $Status.campaign_gate_summary.deterministic_decision } else { '-' })"
    "  hermes:        $(if ($Status.campaign_gate_summary.hermes_decision) { $Status.campaign_gate_summary.hermes_decision } else { '-' })"
    "  final:         $(if ($Status.campaign_gate_summary.final_decision) { Colorize-StatusValue -Kind campaign -Value $Status.campaign_gate_summary.final_decision } else { Colorize-StatusValue -Kind campaign -Value $Status.campaign_gate_summary.decision })"
    "  human:        required=$(if ($Status.campaign_gate_summary.human_approval_required -ne $null) { $Status.campaign_gate_summary.human_approval_required } else { '-' }) present=$(if ($Status.campaign_gate_summary.human_approval_present -ne $null) { $Status.campaign_gate_summary.human_approval_present } else { '-' })"
    "  next_step:     $(if ($Status.campaign_gate_summary.next_step_id) { $Status.campaign_gate_summary.next_step_id } else { '-' })"
    "  input_hash:    $(if ($Status.campaign_gate_summary.input_state_hash) { $Status.campaign_gate_summary.input_state_hash } else { '-' })"
    "  prompt:        $(if ($Status.campaign_gate_summary.prompt_version) { $Status.campaign_gate_summary.prompt_version } else { '-' })"
    if ($Status.campaign_gate_summary.blockers) { "  blockers:      $(@($Status.campaign_gate_summary.blockers) -join ', ')" }
    if ($Status.campaign_gate_summary.warnings) { "  warnings:      $(@($Status.campaign_gate_summary.warnings) -join ', ')" }
  }
  if ($SummaryOnly) { return }
  ""
  "Workers:"
  if (@($Status.workers).Count -eq 0) { "  none" } else {
    "  id                       status   seen         task"
    foreach ($worker in @($Status.workers | Sort-Object worker_id)) {
      "  $(Shorten-StatusText $worker.worker_id 24) $(Shorten-StatusText $worker.status 8) $(Shorten-StatusText $worker.last_seen 12) $(Shorten-StatusText $worker.current_task_id 24)"
    }
  }
  ""
  "Tasks:"
  if (@($Status.tasks).Count -eq 0) { "  none" } else {
    "  id                             status           worker             pr  evidence"
    foreach ($task in @($Status.tasks)) {
      $displayStatus = Colorize-StatusValue -Kind task -Value (Shorten-StatusText $task.display_status 16)
      "  $(Shorten-StatusText $task.task_id 30) $displayStatus $(Shorten-StatusText $task.worker_id 18) $(Shorten-StatusText $task.pr 3) $(Shorten-StatusText $task.evidence 18)"
    }
  }
  if ($Status.filters.show_leases) {
    ""
    "Leases:"
    $leaseRows = @($Status.tasks | Where-Object { $_.lease_id })
    if ($leaseRows.Count -eq 0) { "  none" } else {
      "  task                           status              worker             expires"
      foreach ($task in $leaseRows) {
        $leaseText = Colorize-StatusValue -Kind lease -Value (Shorten-StatusText $task.lease_display_status 18)
        "  $(Shorten-StatusText $task.task_id 30) $leaseText $(Shorten-StatusText $task.lease_worker_id 18) $(Shorten-StatusText $task.lease_expires_at 28)"
      }
    }
  }
  if ($Status.filters.show_proposals) {
    ""
    "Proposals:"
    if (@($Status.proposals).Count -eq 0) { "  none" } else {
      "  id                       review              derived              policy              risk  type         title"
      foreach ($proposal in @($Status.proposals)) {
        $review = Colorize-StatusValue -Kind proposal -Value (Shorten-StatusText $proposal.review_status 19)
        $derived = Colorize-StatusValue -Kind proposal -Value (Shorten-StatusText $proposal.derived_execution_status 19)
        "  $(Shorten-StatusText $proposal.proposal_id 24) $review $derived $(Shorten-StatusText $proposal.policy_decision 19) $(Shorten-StatusText $proposal.risk 5) $(Shorten-StatusText $proposal.task_type 12) $(Shorten-StatusText $proposal.title 42)"
      }
    }
  }
  if ($Status.filters.show_campaigns) {
    ""
    "Campaigns:"
    if (@($Status.campaigns).Count -eq 0) { "  none" } else {
      "  id                         status      current_step              title"
      foreach ($campaign in @($Status.campaigns)) {
        $campaignStatus = Colorize-StatusValue -Kind campaign -Value (Shorten-StatusText $campaign.status 10)
        "  $(Shorten-StatusText $campaign.campaign_id 26) $campaignStatus $(Shorten-StatusText $campaign.current_step_id 25) $(Shorten-StatusText $campaign.title 44)"
      }
    }
  }
  if ($Status.filters.show_campaign_steps) {
    ""
    "Campaign Steps:"
    if (@($Status.campaign_steps).Count -eq 0) { "  none" } else {
      "  order status       gate        goal_id                              title"
      foreach ($step in @($Status.campaign_steps | Sort-Object campaign_id, order)) {
        $stepStatus = Colorize-StatusValue -Kind campaign -Value (Shorten-StatusText $step.status 11)
        $gateStatus = if ($step.gate_summary -and $step.gate_summary.final_decision) { Colorize-StatusValue -Kind campaign -Value (Shorten-StatusText $step.gate_summary.final_decision 10) } else { Shorten-StatusText "-" 10 }
        "  $(Shorten-StatusText $step.order 5) $stepStatus $gateStatus $(Shorten-StatusText $step.goal_id 35) $(Shorten-StatusText $step.title 44)"
      }
    }
  }
  if ($Status.hygiene_findings -and @($Status.hygiene_findings).Count -gt 0) {
    ""
    "Hygiene Findings:"
    foreach ($finding in @($Status.hygiene_findings | Select-Object -First 20)) {
      $findingStatus = Colorize-StatusValue -Kind task -Value (Shorten-StatusText $finding.status 28)
      "  $(Shorten-StatusText $finding.kind 9) $(Shorten-StatusText $finding.id 32) $findingStatus $($finding.recommended_action)"
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($TaskId) -and @($Status.tasks).Count -gt 0) {
    $task = @($Status.tasks)[0]
    ""
    "Task Detail:"
    "  task_id:        $($task.task_id)"
    "  raw_status:     $($task.raw_status)"
    "  display_status: $($task.display_status)"
    "  recovered:      $($task.recovered)"
    "  ci_status:      $(if ($task.ci_status) { $task.ci_status } else { '-' })"
    "  pr_url:         $(if ($task.pr_url) { $task.pr_url } else { '-' })"
    "  lease_id:       $(if ($task.lease_id) { $task.lease_id } else { '-' })"
    "  lease_status:   $(if ($task.lease_status) { $task.lease_status } else { '-' })"
    "  events_shown:   $(@($task.events).Count) of $($task.event_count)"
    "  summary:        $(if ($task.summary) { $task.summary } else { '-' })"
  }
}

function Join-FilterDescription {
  $parts = @()
  if ($ActiveOnly) { $parts += "active-only" }
  if ($TaskStatus.Count -gt 0) { $parts += "status=$($TaskStatus -join ',')" }
  if ($RecoveredOnly) { $parts += "recovered-only" }
  if ($ExcludeRecovered) { $parts += "exclude-recovered" }
  if ($IncludeRecovered) { $parts += "include-recovered" }
  if ($TaskId) { $parts += "task=$TaskId" }
  if ($WorkerId) { $parts += "worker=$WorkerId" }
  if ($Since) { $parts += "since=$Since" }
  if ($Until) { $parts += "until=$Until" }
  if ($ShowAll) { $parts += "show-all" }
  if ($ShowProposals) { $parts += "show-proposals" }
  if ($ShowCampaigns) { $parts += "show-campaigns" }
  if ($ShowCampaignSteps) { $parts += "show-campaign-steps" }
  if ($CampaignId) { $parts += "campaign=$CampaignId" }
  if ($ShowLeases) { $parts += "show-leases" }
  if ($ShowLocks) { $parts += "show-locks" }
  if ($Hygiene) { $parts += "hygiene" }
  if ($StaleOnly) { $parts += "stale-only" }
  if ($BlockedOnly) { $parts += "blocked-only" }
  if ($FailedOnly) { $parts += "failed-only" }
  if ($NeedsReview) { $parts += "needs-review" }
  if ($NeedsReconciliation) { $parts += "needs-reconciliation" }
  if ($ProposalStatus.Count -gt 0) { $parts += "proposal-status=$($ProposalStatus -join ',')" }
  if ($ReviewStatus.Count -gt 0) { $parts += "review-status=$($ReviewStatus -join ',')" }
  if ($ApprovedOnly) { $parts += "approved-only" }
  if ($PendingReviewOnly) { $parts += "pending-review-only" }
  if ($parts.Count -eq 0) { $parts += "recent" }
  return ($parts -join "; ")
}

$config = New-StatusApiConfig
if ($config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

if ($RecentTasks -gt 0) { $TaskLimit = $RecentTasks }
if ($TaskLimit -lt 1) { $TaskLimit = 10 }
if ($ProposalLimit -lt 1) { $ProposalLimit = 10 }
if ($CampaignLimit -lt 1) { $CampaignLimit = 10 }
$sinceDate = if ($Since) { ConvertTo-StatusDate -Value $Since } else { $null }
$untilDate = if ($Until) { ConvertTo-StatusDate -Value $Until } else { $null }
$warnings = @()
if ($Since -and -not $sinceDate) { $warnings += "Could not parse -Since; timestamp filter was ignored." }
if ($Until -and -not $untilDate) { $warnings += "Could not parse -Until; timestamp filter was ignored." }

$health = Invoke-SkyBridgeApi -Method GET -Path "/v1/health" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
$project = $null
try { $project = Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds } catch {}
$control = $null
try { $control = (Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).control_state } catch {}
$workers = (Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).workers
if (-not [string]::IsNullOrWhiteSpace($WorkerId)) {
  $workerResponse = Invoke-SkyBridgeApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $workers = @($workerResponse.worker)
}

$tasks = (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds).tasks
if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
  $taskResponse = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $tasks = @($taskResponse.task)
}

$workerItems = @($workers) | Where-Object { $null -ne $_ }
$taskItems = @($tasks) | Where-Object { $null -ne $_ }
$workerSummaries = @($workerItems | ForEach-Object { Select-WorkerSummary -Worker $_ })
$workerStatusById = @{}
foreach ($worker in @($workerSummaries)) {
  if ($worker.worker_id) { $workerStatusById[[string]$worker.worker_id] = [string]$worker.status }
}
$allTaskSummaries = @($taskItems | ForEach-Object { Select-TaskSummary -Task $_ -WorkerStatusById $workerStatusById })
$filteredTasks = @($allTaskSummaries)
if ($WorkerId) { $filteredTasks = @($filteredTasks | Where-Object { $_.worker_id -eq $WorkerId }) }
if ($ActiveOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.raw_status -in @("queued", "claimed", "running") }) }
if ($RecoveredOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.recovered }) }
elseif ($ExcludeRecovered -or (-not $IncludeRecovered -and @($TaskStatus | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains "failed")) {
  $filteredTasks = @($filteredTasks | Where-Object { -not $_.recovered })
}
if ($TaskStatus.Count -gt 0) { $filteredTasks = @($filteredTasks | Where-Object { Test-TaskStatusMatch -Task $_ -Statuses $TaskStatus }) }
if ($StaleOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.task_hygiene_status -in @("stale_claim", "stale_running", "lease_expired") -or $_.lease_display_status -in @("expired", "stale", "inconsistent") }) }
if ($BlockedOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.raw_status -eq "blocked" }) }
if ($FailedOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.raw_status -eq "failed" -and -not $_.recovered }) }
if ($NeedsReconciliation) { $filteredTasks = @($filteredTasks | Where-Object { $_.task_hygiene_status -eq "pr_merged_needs_evidence" -or $_.lease_display_status -in @("expired", "stale", "inconsistent") }) }
if (-not $ShowAll -and -not $ShowCompleted -and -not $TaskId -and -not $ActiveOnly -and $TaskStatus.Count -eq 0 -and -not $RecoveredOnly) {
  $filteredTasks = @($filteredTasks | Where-Object { $_.raw_status -ne "completed" -or $_.recovered })
}
if ($sinceDate -or $untilDate) {
  $filteredTasks = @($filteredTasks | Where-Object {
    $candidate = ConvertTo-StatusDate -Value $(if ($SortBy -eq "created_at") { $_.created_at } elseif ($SortBy -eq "last_event") { $_.last_event_at } else { $_.updated_at })
    if (-not $candidate) {
      $warnings += "Task $($_.task_id) has no comparable timestamp."
      $true
    } elseif ($sinceDate -and $candidate -lt $sinceDate) {
      $false
    } elseif ($untilDate -and $candidate -gt $untilDate) {
      $false
    } else {
      $true
    }
  })
}
$sortedTasks = @($filteredTasks | Sort-Object -Property @{ Expression = { Get-TaskSortValue -Task $_ }; Descending = [bool]$Descending })
if (-not $Descending -and $SortBy -ne "status") { $sortedTasks = @($filteredTasks | Sort-Object -Property @{ Expression = { Get-TaskSortValue -Task $_ }; Descending = $true }) }
$totalFiltered = $sortedTasks.Count
$shownTasks = if ($ShowAll -or $TaskId) { @($sortedTasks) } else { @($sortedTasks | Select-Object -First $TaskLimit) }
$shownTasks = @($shownTasks) | Where-Object { $null -ne $_ }
$shownWorkers = if ($Json) { $workerSummaries } else { @($workerSummaries | Select-Object -First $WorkersLimit) }
$truncated = (-not $ShowAll -and -not $TaskId -and $totalFiltered -gt @($shownTasks).Count)

$allProposalSummaries = @()
$filteredProposals = @()
$shownProposals = @()
if ($ShowProposals -or $Hygiene -or $NeedsReview -or $NeedsReconciliation -or $ReconcileProposals) {
  $proposalPayload = Invoke-SkyBridgeApi -Method GET -Path "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $proposalItems = @($proposalPayload.proposals) | Where-Object { $null -ne $_ }
  $taskIndex = @{}
  foreach ($task in @($allTaskSummaries)) {
    if ($task.task_id) { $taskIndex[[string]$task.task_id] = $task }
  }
  $allProposalSummaries = @($proposalItems | ForEach-Object { Select-ProposalSummary -Proposal $_ -TaskIndex $taskIndex })
  $filteredProposals = @($allProposalSummaries)
  if ($ProposalStatus.Count -gt 0) {
    $wanted = @($ProposalStatus | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $filteredProposals = @($filteredProposals | Where-Object { $wanted -contains ([string]$_.status).ToLowerInvariant() })
  }
  if ($ReviewStatus.Count -gt 0) {
    $wantedReview = @($ReviewStatus | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $filteredProposals = @($filteredProposals | Where-Object { $wantedReview -contains ([string]$_.review_status).ToLowerInvariant() })
  }
  if ($ApprovedOnly) {
    $filteredProposals = @($filteredProposals | Where-Object { $_.status -eq "approved" -or $_.review_status -eq "approved" })
  }
  if ($PendingReviewOnly) {
    $filteredProposals = @($filteredProposals | Where-Object { $_.status -eq "proposed" -or $_.review_status -eq "proposed" -or $_.review_status -eq "reviewed" })
  }
  if ($NeedsReview) {
    $filteredProposals = @($filteredProposals | Where-Object { $_.review_status -in @("proposed", "reviewed") -or $_.status -in @("proposed", "reviewed") })
  }
  if ($NeedsReconciliation) {
    $filteredProposals = @($filteredProposals | Where-Object { $_.derived_execution_status -in @("approved_unconverted", "converted_unexecuted") })
  }
  $shownProposals = if ($ShowAll) { @($filteredProposals) } else { @($filteredProposals | Select-Object -First $ProposalLimit) }
  $shownProposals = @($shownProposals) | Where-Object { $null -ne $_ }
}

$allCampaignSummaries = @()
$shownCampaigns = @()
$campaignStepSummaries = @()
$campaignGateSummary = $null
if ($ShowCampaigns -or $CampaignId -or $ShowCampaignSteps) {
  try {
    if ($CampaignId) {
      $campaignPayload = Invoke-SkyBridgeApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
      $allCampaignSummaries = @($campaignPayload.campaign | Where-Object { $null -ne $_ } | ForEach-Object { Select-CampaignSummary -Campaign $_ })
      $campaignStepSummaries = @($campaignPayload.steps | Where-Object { $null -ne $_ } | ForEach-Object { Select-CampaignStepSummary -Step $_ })
      try {
        $gatePayload = Invoke-SkyBridgeApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance-preview" -Body @{} -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
        $campaignGateSummary = $gatePayload.gate
      } catch {
        $warnings += "Campaign advance-preview unavailable for $CampaignId."
      }
    } else {
      $campaignPayload = Invoke-SkyBridgeApi -Method GET -Path "/v1/campaigns?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
      $allCampaignSummaries = @($campaignPayload.campaigns | Where-Object { $null -ne $_ } | ForEach-Object { Select-CampaignSummary -Campaign $_ })
      if ($ShowCampaignSteps) {
        foreach ($campaign in @($allCampaignSummaries | Select-Object -First $CampaignLimit)) {
          $stepsPayload = Invoke-SkyBridgeApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($campaign.campaign_id))/steps" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
          $campaignStepSummaries += @($stepsPayload.steps | Where-Object { $null -ne $_ } | ForEach-Object { Select-CampaignStepSummary -Step $_ })
        }
      }
    }
    $shownCampaigns = @(if ($ShowAll -or $CampaignId) { @($allCampaignSummaries) } else { @($allCampaignSummaries | Select-Object -First $CampaignLimit) })
  } catch {
    $warnings += "Campaign endpoints unavailable or failed: $($_.Exception.Message)"
  }
}

$hygieneReport = if ($Hygiene) { Get-HygieneReport -Tasks $allTaskSummaries -Proposals $allProposalSummaries -Workers $workerSummaries } else { $null }

$status = [pscustomobject]@{
  ok = $true
  api_base = $ApiBase
  project_id = $ProjectId
  token_printed = $false
  health = [pscustomobject]@{ ok = [bool]$health.ok; status = if ($health.ok) { "ok" } else { "unknown" }; persistence = $health.persistence }
  project = $project.project
  control = if ($control) { $control } else { [pscustomobject]@{ state = "unknown"; stop_requested = $false } }
  display_header = [pscustomobject]@{
    api = $ApiBase
    health = if ($health.ok) { "ok" } else { "unknown" }
    project = $ProjectId
    control = if ($control) { $control.state } else { "unknown" }
    stop_requested = if ($control) { [bool]$control.stop_requested } else { $false }
    reason = if ($control -and $control.stop_reason) { [string]$control.stop_reason } else { $null }
  }
  control_summary = [pscustomobject]@{
    state = if ($control) { $control.state } else { "unknown" }
    stop_requested = if ($control) { [bool]$control.stop_requested } else { $false }
    stop_reason = if ($control -and $control.stop_reason) { [string]$control.stop_reason } else { $null }
    degraded_reason = if ($control -and $control.degraded_reason) { [string]$control.degraded_reason } else { $null }
  }
  task_summary = Get-TaskSummaryCounts -Tasks $allTaskSummaries -Matching $sortedTasks -Shown $shownTasks -Truncated $truncated
  proposal_summary = if ($ShowProposals -or $Hygiene -or $ReconcileProposals) { Get-ProposalSummaryCounts -Proposals $allProposalSummaries } else { $null }
  campaign_summary = if ($ShowCampaigns -or $CampaignId -or $ShowCampaignSteps) { Get-CampaignSummaryCounts -Campaigns $allCampaignSummaries } else { $null }
  hygiene_summary = if ($hygieneReport) { $hygieneReport.summary } else { $null }
  hygiene_findings = if ($hygieneReport) { @($hygieneReport.findings) } else { $null }
  recommended_actions = if ($hygieneReport) { @($hygieneReport.recommended_actions) } else { $null }
  workers = $shownWorkers
  tasks = @($shownTasks)
  proposals = if ($ShowProposals -or $Hygiene -or $ReconcileProposals) { @($shownProposals) } else { $null }
  campaigns = if ($ShowCampaigns -or $CampaignId -or $ShowCampaignSteps) { @($shownCampaigns) } else { $null }
  campaign_steps = if ($ShowCampaignSteps -or $CampaignId) { @($campaignStepSummaries) } else { $null }
  campaign_gate_summary = $campaignGateSummary
  warnings = @($warnings | Select-Object -Unique)
  filters = [pscustomobject]@{
    description = Join-FilterDescription
    task_limit = $TaskLimit
    workers_limit = $WorkersLimit
    recent_tasks = $RecentTasks
    task_status = @($TaskStatus)
    active_only = [bool]$ActiveOnly
    recovered_only = [bool]$RecoveredOnly
    include_recovered = [bool]$IncludeRecovered
    exclude_recovered = [bool]$ExcludeRecovered
    show_completed = [bool]$ShowCompleted
    show_all = [bool]$ShowAll
    summary_only = [bool]$SummaryOnly
    show_proposals = [bool]$ShowProposals
    show_campaigns = [bool]($ShowCampaigns -or $CampaignId)
    show_campaign_steps = [bool]($ShowCampaignSteps -or $CampaignId)
    show_leases = [bool]$ShowLeases
    show_locks = [bool]$ShowLocks
    hygiene = [bool]$Hygiene
    stale_only = [bool]$StaleOnly
    blocked_only = [bool]$BlockedOnly
    failed_only = [bool]$FailedOnly
    needs_review = [bool]$NeedsReview
    needs_reconciliation = [bool]$NeedsReconciliation
    reconcile_proposals = [bool]$ReconcileProposals
    color_mode = if ($NoColor) { "Never" } elseif ($Color) { "Always" } else { $ColorMode }
    color_enabled = [bool]$script:StatusColorEnabled
    proposal_limit = $ProposalLimit
    campaign_limit = $CampaignLimit
    campaign_id = if ($CampaignId) { $CampaignId } else { $null }
    proposal_status = @($ProposalStatus)
    review_status = @($ReviewStatus)
    approved_only = [bool]$ApprovedOnly
    pending_review_only = [bool]$PendingReviewOnly
    include_events = [bool]$IncludeEvents
    event_limit = $EventLimit
    task_id = if ($TaskId) { $TaskId } else { $null }
    worker_id = if ($WorkerId) { $WorkerId } else { $null }
    sort_by = $SortBy
    descending = [bool]$Descending
    truncated = $truncated
    total_filtered = $totalFiltered
    proposal_filtered = @($filteredProposals).Count
  }
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
  $outputDir = Split-Path -Parent $OutputFile
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
  $status | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $status | ConvertTo-Json -Depth 40 -Compress
} else {
  Write-CompactStatus -Status $status
}
