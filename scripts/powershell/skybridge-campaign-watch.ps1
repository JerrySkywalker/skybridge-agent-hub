[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$TokenEnvVar,
  [Alias("IntervalSeconds")]
  [int]$PollIntervalSeconds = 5,
  [int]$RenderIntervalMilliseconds = 250,
  [switch]$SpinnerOnlyBetweenPolls,
  [int]$MaxFrames = 0,
  [ValidateSet("Auto", "Always", "Never")]
  [string]$ColorMode = "Auto",
  [switch]$Once,
  [switch]$NoClear,
  [switch]$Compact,
  [switch]$ShowEvents,
  [int]$EventLimit = 8,
  [switch]$Json,
  [string]$OutputFile,
  [switch]$Demo,
  [int]$Frames = 6
)

$ErrorActionPreference = "Stop"

$SpinnerFrames = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")

function Test-ColorEnabled {
  if ($Json) { return $false }
  if ($ColorMode -eq "Always") { return $true }
  if ($ColorMode -eq "Never") { return $false }
  return -not [Console]::IsOutputRedirected
}

$script:UseColor = Test-ColorEnabled

function Colorize {
  param([string]$Text, [string]$Kind)
  if (-not $script:UseColor) { return $Text }
  $code = switch -Regex ($Kind) {
    "ok|completed|passed|online|green" { "32"; break }
    "running|current|cyan" { "36"; break }
    "pending|warning|held|stale|yellow" { "33"; break }
    "failed|blocker|offline|red" { "31"; break }
    "dim|gray|inactive|skipped" { "2"; break }
    default { "0" }
  }
  return "$([char]27)[$code" + "m$Text$([char]27)[0m"
}

function Get-StatusKind {
  param([string]$Status)
  switch -Regex ([string]$Status) {
    "ok|completed|passed|online|recovered|released" { "ok"; break }
    "running|current|ready" { "running"; break }
    "pending|warning|held|stale|draft|paused" { "pending"; break }
    "failed|blocker|offline|aborted|stopped" { "failed"; break }
    default { "dim" }
  }
}

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  return ($output | ConvertFrom-Json)
}

function Get-ScriptTokenArgs {
  $args = @()
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  return $args
}

function Get-DemoFrame {
  param([int]$FrameIndex)
  $steps = @(
    [pscustomobject]@{ order = 1; goal_id = "super-189-ci-guardian-pr-finalizer-hardening"; title = "CI Guardian and PR Finalizer Hardening"; status = "ready"; linked_task_ids = @(); linked_pr_urls = @() },
    [pscustomobject]@{ order = 2; goal_id = "super-190-campaign-run-report-evidence-ledger"; title = "Campaign Run Report and Evidence Ledger"; status = "pending"; linked_task_ids = @(); linked_pr_urls = @() },
    [pscustomobject]@{ order = 3; goal_id = "super-191-readonly-operator-dashboard"; title = "Read-only Operator Dashboard"; status = "pending"; linked_task_ids = @(); linked_pr_urls = @() }
  )
  $states = @(
    @{ runner = "idle"; hold = "preflight"; stepStatus = "ready"; task = "-"; pr = "-"; checks = "-"; evidence = "-"; gate = "ready" },
    @{ runner = "running"; hold = ""; stepStatus = "running"; task = "campaign-step-super-189-demo"; pr = "-"; checks = "-"; evidence = "-"; gate = "executing" },
    @{ runner = "running"; hold = ""; stepStatus = "running"; task = "campaign-step-super-189-demo"; pr = "#101"; checks = "pending 2/4"; evidence = "-"; gate = "waiting_for_ci" },
    @{ runner = "running"; hold = ""; stepStatus = "running"; task = "campaign-step-super-189-demo"; pr = "#101"; checks = "passed 4/4"; evidence = "repaired"; gate = "ready_to_advance" },
    @{ runner = "running"; hold = ""; stepStatus = "completed"; task = "campaign-step-super-189-demo"; pr = "#101"; checks = "passed 4/4"; evidence = "complete"; gate = "advance" },
    @{ runner = "held"; hold = "ci_failed"; stepStatus = "failed"; task = "campaign-step-super-189-demo"; pr = "#101"; checks = "failed 1/4"; evidence = "missing"; gate = "held_failure" }
  )
  $state = $states[[Math]::Min($FrameIndex, $states.Count - 1)]
  $steps[0].status = $state.stepStatus
  [pscustomobject]@{
    ok = $true
    demo = $true
    api_base = "demo"
    project_id = $ProjectId
    token_printed = $false
    fetched_at = (Get-Date)
    warning = $null
    project = [pscustomobject]@{ control = "paused"; active_tasks = 0; stale_leases = 0; stale_locks = 0 }
    worker = [pscustomobject]@{ worker_id = "laptop-zenbookduo"; status = "online"; last_seen = "now"; current_task_id = $null }
    campaign = [pscustomobject]@{ campaign_id = $CampaignId; status = "draft"; current_step_id = "$CampaignId`:super-189-ci-guardian-pr-finalizer-hardening" }
    runner = [pscustomobject]@{ status = $state.runner; hold_reason = $state.hold; audit_log = @(
      [pscustomobject]@{ at = "10:34:01"; decision = "task.created"; step_id = "super-189"; reason = "demo" },
      [pscustomobject]@{ at = "10:34:03"; decision = "task.claimed"; step_id = "super-189"; reason = "demo" },
      [pscustomobject]@{ at = "10:40:48"; decision = "pr.created"; step_id = "super-189"; reason = "#101" }
    ) }
    steps = $steps
    current_step = [pscustomobject]@{ index = 1; total = 12; goal_id = $steps[0].goal_id; title = $steps[0].title; status = $state.stepStatus; task_id = $state.task; pr = $state.pr; checks = $state.checks; evidence = $state.evidence; gate = $state.gate }
  }
}

function Get-WatchSnapshot {
  $tokenArgs = Get-ScriptTokenArgs
  $activeArgs = @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-ActiveOnly", "-Json", "-ColorMode", "Never")
  $hygieneArgs = @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ShowLocks", "-ColorMode", "Never", "-Json")
  $campaignArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json")
  $runnerArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json")
  $active = Invoke-JsonScript $activeArgs
  $hygiene = Invoke-JsonScript $hygieneArgs
  $campaign = Invoke-JsonScript $campaignArgs
  $runner = Invoke-JsonScript $runnerArgs

  $steps = @($campaign.steps | Sort-Object order)
  $currentStepId = if ($runner.current_step_id) { [string]$runner.current_step_id } elseif ($campaign.campaign.current_step_id) { [string]$campaign.campaign.current_step_id } else { $null }
  $current = @($steps | Where-Object { $_.campaign_step_id -eq $currentStepId })[0]
  if (-not $current -and $steps.Count -gt 0) { $current = $steps[0] }
  $index = if ($current) { [int]$current.order } else { 0 }
  $taskId = if ($current -and @($current.linked_task_ids).Count -gt 0) { [string]@($current.linked_task_ids)[0] } else { "-" }
  $pr = if ($current -and @($current.linked_pr_urls).Count -gt 0) { [string]@($current.linked_pr_urls)[0] } else { "-" }
  [pscustomobject]@{
    ok = $true
    demo = $false
    api_base = $ApiBase
    project_id = $ProjectId
    token_printed = $false
    fetched_at = (Get-Date)
    warning = $null
    project = [pscustomobject]@{
      control = [string]$active.control.state
      active_tasks = [int]$active.task_summary.active
      stale_leases = [int]$hygiene.task_summary.stale_leases
      stale_locks = if ($hygiene.hygiene_summary.stale_locks) { [int]$hygiene.hygiene_summary.stale_locks } else { 0 }
    }
    worker = @($active.workers | Where-Object { $_.worker_id -eq "laptop-zenbookduo" })[0]
    campaign = $campaign.campaign
    runner = [pscustomobject]@{
      status = if ($runner.runner_state.runner_status) { [string]$runner.runner_state.runner_status } else { [string]$runner.runner_lock_status }
      hold_reason = if ($runner.runner_state.hold_reason) { [string]$runner.runner_state.hold_reason } else { "-" }
      audit_log = @($runner.runner_state.audit_log)
    }
    steps = $steps
    current_step = [pscustomobject]@{
      index = $index
      total = @($steps).Count
      goal_id = if ($current) { [string]$current.goal_id } else { "-" }
      title = if ($current) { [string]$current.title } else { "-" }
      status = if ($current) { [string]$current.status } else { "-" }
      task_id = $taskId
      pr = $pr
      checks = "-"
      evidence = "-"
      gate = if ($campaign.gate.decision) { [string]$campaign.gate.decision } else { "-" }
    }
  }
}

function Format-StepLine {
  param($Step, [int]$Total, [bool]$Current)
  $marker = if ($Current) { "▸" } else { " " }
  $status = [string]$Step.status
  $line = "{0} {1:00}/{2:00}  {3,-62} {4}" -f $marker, [int]$Step.order, $Total, [string]$Step.goal_id, $status.ToUpperInvariant()
  $kind = if ($Current) { "current" } else { Get-StatusKind $status }
  Colorize $line $kind
}

function Format-WatchFrame {
  param($Snapshot, [string]$Spinner)
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $age = "-"
  if ($Snapshot.fetched_at) {
    try { $age = "{0:N1}s" -f ((Get-Date) - ([datetime]$Snapshot.fetched_at)).TotalSeconds } catch { $age = "-" }
  }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add(("$(Colorize $Spinner 'cyan') SkyBridge Dev Queue Watch                                      $timestamp")) | Out-Null
  $lines.Add("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━") | Out-Null
  if ($Snapshot.warning) {
    $lines.Add((Colorize (" WARNING     {0}" -f $Snapshot.warning) "red")) | Out-Null
  }
  $control = Colorize ([string]$Snapshot.project.control) (Get-StatusKind ([string]$Snapshot.project.control))
  $workerStatus = if ($Snapshot.worker) { [string]$Snapshot.worker.status } else { "unknown" }
  $workerLineStatus = Colorize $workerStatus (Get-StatusKind $workerStatus)
  $runnerStatus = Colorize ([string]$Snapshot.runner.status) (Get-StatusKind ([string]$Snapshot.runner.status))
  $lines.Add((" Project     {0,-28} control={1,-16} active={2} stale_leases={3} stale_locks={4}" -f $Snapshot.project_id, $control, $Snapshot.project.active_tasks, $Snapshot.project.stale_leases, $Snapshot.project.stale_locks)) | Out-Null
  $workerTask = if ($Snapshot.worker.current_task_id) { $Snapshot.worker.current_task_id } else { "-" }
  $lines.Add((" Worker      {0,-28} {1,-18} task={2}" -f "laptop-zenbookduo", $workerLineStatus, $workerTask)) | Out-Null
  $lines.Add((" Campaign    {0,-28} runner={1,-16} step={2:00}/{3:00} refreshed={4}" -f $Snapshot.campaign.campaign_id, $runnerStatus, $Snapshot.current_step.index, $Snapshot.current_step.total, $age)) | Out-Null
  if ($Compact) {
    $lines.Add((" Current     {0}  {1}  hold={2}" -f $Snapshot.current_step.goal_id, $Snapshot.current_step.title, $Snapshot.runner.hold_reason)) | Out-Null
    return ($lines -join "`n")
  }
  $lines.Add("") | Out-Null
  $lines.Add("Current Step") | Out-Null
  $lines.Add(("   {0:00}/{1:00}  {2}" -f $Snapshot.current_step.index, $Snapshot.current_step.total, $Snapshot.current_step.title)) | Out-Null
  $lines.Add(("  goal:     {0}" -f $Snapshot.current_step.goal_id)) | Out-Null
  $lines.Add(("  task:     {0}" -f $Snapshot.current_step.task_id)) | Out-Null
  $lines.Add(("  PR:       {0}" -f $Snapshot.current_step.pr)) | Out-Null
  $lines.Add(("  checks:   {0}" -f $Snapshot.current_step.checks)) | Out-Null
  $lines.Add(("  evidence: {0}" -f $Snapshot.current_step.evidence)) | Out-Null
  $lines.Add(("  gate:     {0}" -f $Snapshot.current_step.gate)) | Out-Null
  $lines.Add(("  hold:     {0}" -f $Snapshot.runner.hold_reason)) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Queue") | Out-Null
  $window = if ($Compact) { 2 } else { 3 }
  foreach ($step in @($Snapshot.steps | Sort-Object order | Where-Object { [Math]::Abs([int]$_.order - [int]$Snapshot.current_step.index) -le $window })) {
    $lines.Add((Format-StepLine -Step $step -Total $Snapshot.current_step.total -Current ([int]$step.order -eq [int]$Snapshot.current_step.index))) | Out-Null
  }
  if ($ShowEvents -or @($Snapshot.runner.audit_log).Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("Recent Events") | Out-Null
    $events = @($Snapshot.runner.audit_log | Select-Object -Last $EventLimit)
    if ($events.Count -eq 0) { $lines.Add("  -") | Out-Null }
    foreach ($event in $events) {
      $when = if ($event.at) { ([string]$event.at) } else { "-" }
      if ($when.Length -gt 8) { $when = $when.Substring(0, [Math]::Min(19, $when.Length)) }
      $lines.Add(("  {0,-19}  {1}  {2}" -f $when, $event.decision, $event.reason)) | Out-Null
    }
  }
  return ($lines -join "`n")
}

function Write-WatchResult {
  param($Snapshot, [string]$Frame)
  $result = [pscustomobject]@{
    ok = $true
    command = "watch"
    mode = if ($Demo) { "demo" } else { "read" }
    token_printed = $false
    snapshot = $Snapshot
    frame = $Frame
  }
if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $result | ConvertTo-Json -Depth 80 -Compress }
  else { $Frame }
}

if ($PollIntervalSeconds -lt 1) { throw "-PollIntervalSeconds must be at least 1." }
if ($RenderIntervalMilliseconds -lt 50) { throw "-RenderIntervalMilliseconds must be at least 50." }
if ($EventLimit -lt 1) { throw "-EventLimit must be at least 1." }

$frameIndex = 0
$snapshot = $null
$lastPoll = [datetime]::MinValue
$effectiveOnce = [bool]($Once -or $Json)
$effectiveMaxFrames = if ($MaxFrames -gt 0) { $MaxFrames } elseif ($Demo -and $Frames -gt 0) { $Frames } else { 0 }
try {
  do {
    $spinner = $SpinnerFrames[$frameIndex % $SpinnerFrames.Count]
    $shouldPoll = $Demo -or $null -eq $snapshot -or ((Get-Date) - $lastPoll).TotalSeconds -ge $PollIntervalSeconds
    try {
      if ($shouldPoll) {
        if ($env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL -and $frameIndex -ge 1) {
          throw "simulated poll failure"
        }
        $snapshot = if ($Demo) { Get-DemoFrame -FrameIndex ($frameIndex % [Math]::Max(1, $Frames)) } else { Get-WatchSnapshot }
        $lastPoll = Get-Date
      } elseif ($SpinnerOnlyBetweenPolls -and $snapshot.PSObject.Properties["warning"]) {
        $snapshot.warning = $null
      }
      $frame = Format-WatchFrame -Snapshot $snapshot -Spinner $spinner
    } catch {
      if ($null -ne $snapshot) {
        $snapshot.warning = $_.Exception.Message
        $frame = Format-WatchFrame -Snapshot $snapshot -Spinner $spinner
      } else {
        $snapshot = [pscustomobject]@{
          ok = $false
          token_printed = $false
          fetched_at = $null
          warning = $_.Exception.Message
          error = $_.Exception.Message
        }
        $frame = "$(Colorize $spinner 'cyan') SkyBridge Dev Queue Watch  $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))`n" +
          (Colorize "WARNING: $($_.Exception.Message)" "red")
      }
      if ($effectiveOnce) { Write-WatchResult -Snapshot $snapshot -Frame $frame; break }
    }
    if (-not $NoClear -and -not $Json -and -not $OutputFile) { try { Clear-Host } catch {} }
    Write-WatchResult -Snapshot $snapshot -Frame $frame
    $frameIndex++
    if ($effectiveOnce) { break }
    if ($effectiveMaxFrames -gt 0 -and $frameIndex -ge $effectiveMaxFrames) { break }
    Start-Sleep -Milliseconds $RenderIntervalMilliseconds
  } while ($true)
} finally {
}
