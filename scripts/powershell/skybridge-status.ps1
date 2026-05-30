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
  [switch]$ShowLeases,
  [switch]$ShowLocks,
  [int]$WorkersLimit = 12,
  [switch]$ShowCompleted,
  [switch]$ShowAll,
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

function Select-TaskSummary {
  param($Task)
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
    lease_expires_at = if ($lease -and $lease.lease_expires_at) { [string]$lease.lease_expires_at } else { $null }
    lease_worker_id = if ($lease -and $lease.worker_id) { [string]$lease.worker_id } else { $null }
    lease_stale_reason = if ($lease -and $lease.stale_reason) { [string]$lease.stale_reason } else { $null }
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
    active_leases = @($taskRows | Where-Object { $_.lease_status -eq "active" }).Count
    stale_leases = @($taskRows | Where-Object { $_.lease_status -in @("expired", "abandoned") }).Count
    total = @($taskRows).Count
    matching = @($matchingRows).Count
    shown = @($shownRows).Count
    truncated = $Truncated
    total_shown = @($shownRows).Count
    total_available = @($taskRows).Count
  }
}

function Select-ProposalSummary {
  param($Proposal)
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
    converted_task_id = if ($Proposal.converted_task_id) { [string]$Proposal.converted_task_id } else { $null }
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
    total = @($Proposals).Count
  }
  foreach ($proposal in @($Proposals)) {
    $key = if ($proposal.review_status) { [string]$proposal.review_status } else { [string]$proposal.status }
    if ($counts.Contains($key)) { $counts[$key] = [int]$counts[$key] + 1 }
  }
  [pscustomobject]$counts
}

function Write-CompactStatus {
  param($Status)
  "SkyBridge"
  "  API:      $($Status.api_base)"
  "  Health:   $($Status.health.status)"
  "  Project:  $($Status.project_id)"
  "  Control:  $($Status.control.state)"
  "  StopReq:  $($Status.control.stop_requested)"
  if ($Status.control.stop_reason) { "  Reason:   $($Status.control.stop_reason)" }
  if ($Status.control.degraded_reason) { "  Degraded: $($Status.control.degraded_reason)" }
  ""
  "Task Summary:"
  "  Active:"
  "    queued:   $($Status.task_summary.queued)"
  "    claimed:  $($Status.task_summary.claimed)"
  "    running:  $($Status.task_summary.running)"
  "    total:    $($Status.task_summary.active)"
  ""
  "  Outcomes:"
  "    completed:          $($Status.task_summary.completed)"
  "    recovered:          $($Status.task_summary.recovered)"
  "    blocked:            $($Status.task_summary.blocked)"
  "    failed_unrecovered: $($Status.task_summary.failed_unrecovered)"
  ""
  "  Display:"
  "    total:      $($Status.task_summary.total)"
  "    matching:   $($Status.task_summary.matching)"
  "    shown:      $($Status.task_summary.shown)"
  "    truncated:  $($Status.task_summary.truncated)"
  if ($Status.filters.show_leases) {
    ""
    "  Leases:"
    "    active: $($Status.task_summary.active_leases)"
    "    stale:  $($Status.task_summary.stale_leases)"
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
      "  $(Shorten-StatusText $task.task_id 30) $(Shorten-StatusText $task.display_status 16) $(Shorten-StatusText $task.worker_id 18) $(Shorten-StatusText $task.pr 3) $(Shorten-StatusText $task.evidence 18)"
    }
  }
  if ($Status.filters.show_leases) {
    ""
    "Leases:"
    $leaseRows = @($Status.tasks | Where-Object { $_.lease_id })
    if ($leaseRows.Count -eq 0) { "  none" } else {
      "  task                           status    worker             expires"
      foreach ($task in $leaseRows) {
        "  $(Shorten-StatusText $task.task_id 30) $(Shorten-StatusText $task.lease_status 9) $(Shorten-StatusText $task.lease_worker_id 18) $(Shorten-StatusText $task.lease_expires_at 28)"
      }
    }
  }
  if ($Status.filters.show_proposals) {
    ""
    "Proposals:"
    if (@($Status.proposals).Count -eq 0) { "  none" } else {
      "  id                       review              policy              risk  type         title"
      foreach ($proposal in @($Status.proposals)) {
        "  $(Shorten-StatusText $proposal.proposal_id 24) $(Shorten-StatusText $proposal.review_status 19) $(Shorten-StatusText $proposal.policy_decision 19) $(Shorten-StatusText $proposal.risk 5) $(Shorten-StatusText $proposal.task_type 12) $(Shorten-StatusText $proposal.title 42)"
      }
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
  if ($ShowLeases) { $parts += "show-leases" }
  if ($ShowLocks) { $parts += "show-locks" }
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
$allTaskSummaries = @($taskItems | ForEach-Object { Select-TaskSummary -Task $_ })
$filteredTasks = @($allTaskSummaries)
if ($WorkerId) { $filteredTasks = @($filteredTasks | Where-Object { $_.worker_id -eq $WorkerId }) }
if ($ActiveOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.raw_status -in @("queued", "claimed", "running") }) }
if ($RecoveredOnly) { $filteredTasks = @($filteredTasks | Where-Object { $_.recovered }) }
elseif ($ExcludeRecovered -or (-not $IncludeRecovered -and @($TaskStatus | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains "failed")) {
  $filteredTasks = @($filteredTasks | Where-Object { -not $_.recovered })
}
if ($TaskStatus.Count -gt 0) { $filteredTasks = @($filteredTasks | Where-Object { Test-TaskStatusMatch -Task $_ -Statuses $TaskStatus }) }
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
if ($ShowProposals) {
  $proposalPayload = Invoke-SkyBridgeApi -Method GET -Path "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  $proposalItems = @($proposalPayload.proposals) | Where-Object { $null -ne $_ }
  $allProposalSummaries = @($proposalItems | ForEach-Object { Select-ProposalSummary -Proposal $_ })
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
  $shownProposals = if ($ShowAll) { @($filteredProposals) } else { @($filteredProposals | Select-Object -First $ProposalLimit) }
  $shownProposals = @($shownProposals) | Where-Object { $null -ne $_ }
}

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
  proposal_summary = if ($ShowProposals) { Get-ProposalSummaryCounts -Proposals $allProposalSummaries } else { $null }
  workers = $shownWorkers
  tasks = @($shownTasks)
  proposals = if ($ShowProposals) { @($shownProposals) } else { $null }
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
    show_leases = [bool]$ShowLeases
    show_locks = [bool]$ShowLocks
    proposal_limit = $ProposalLimit
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
