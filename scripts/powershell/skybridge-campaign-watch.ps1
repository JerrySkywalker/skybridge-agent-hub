[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.example.com" }),
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
  [ValidateSet("Compact", "Normal", "Debug")]
  [string]$Layout = "Normal",
  [switch]$DebugMode,
  [switch]$ShowEvents,
  [int]$EventLimit = 8,
  [switch]$Json,
  [string]$OutputFile,
  [string]$FixtureFile,
  [switch]$SnapshotJson,
  [int]$SnapshotFrameIndex = 0,
  [switch]$Demo,
  [int]$Frames = 6
)

$ErrorActionPreference = "Stop"

$SpinnerFrames = @("|", "/", "-", "\")

function Test-ColorEnabled {
  if ($Json) { return $false }
  if ($ColorMode -eq "Always") { return $true }
  if ($ColorMode -eq "Never") { return $false }
  return -not [Console]::IsOutputRedirected
}

$script:UseColor = Test-ColorEnabled
$script:EffectiveLayout = if ($Compact) { "Compact" } elseif ($DebugMode) { "Debug" } else { $Layout }

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

function Get-PrNumber {
  param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return "-" }
  $match = [regex]::Match($Url, '/pull/(\d+)(?:\D|$)')
  if ($match.Success) { return "#$($match.Groups[1].Value)" }
  return $Url
}

function Get-FirstValue {
  param($Object, [string[]]$Names, [string]$Default = "-")
  foreach ($name in $Names) {
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($name) -and -not [string]::IsNullOrWhiteSpace([string]$Object[$name])) {
      return [string]$Object[$name]
    }
    if ($null -ne $Object -and $Object.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Object.$name)) {
      return [string]$Object.$name
    }
  }
  return $Default
}

function Get-EvidenceStatus {
  param($Step, $Task)
  $evidence = $null
  if ($null -ne $Step -and $Step.PSObject.Properties["evidence_summary"]) { $evidence = $Step.evidence_summary }
  if ($null -eq $evidence -and $null -ne $Task -and $Task.PSObject.Properties["result"] -and $Task.result.PSObject.Properties["evidence_summary"]) {
    $evidence = $Task.result.evidence_summary
  }
  if ($null -eq $evidence) { return "missing" }
  if ($evidence.recovered -eq $true) { return "recovered" }
  return (Get-FirstValue -Object $evidence -Names @("evidence_status", "validation_status", "status") -Default "present")
}

function Get-CiStatus {
  param($Step, $Task)
  if ($null -ne $Step -and $Step.PSObject.Properties["evidence_summary"]) {
    $ci = Get-FirstValue -Object $Step.evidence_summary -Names @("ci_status", "checks", "check_status") -Default ""
    if (-not [string]::IsNullOrWhiteSpace($ci)) { return $ci }
  }
  if ($null -ne $Task) {
    $ci = Get-FirstValue -Object $Task -Names @("ci_status", "check_status") -Default ""
    if (-not [string]::IsNullOrWhiteSpace($ci)) { return $ci }
    if ($Task.PSObject.Properties["result"] -and $Task.result.PSObject.Properties["evidence_summary"]) {
      $ci = Get-FirstValue -Object $Task.result.evidence_summary -Names @("ci_status", "checks", "check_status") -Default ""
      if (-not [string]::IsNullOrWhiteSpace($ci)) { return $ci }
    }
  }
  return "-"
}

function Get-FinalizerPhase {
  param($Step, $Task)
  foreach ($object in @($Step, $Task, $(if ($Task -and $Task.PSObject.Properties["result"]) { $Task.result } else { $null }))) {
    $phase = Get-FirstValue -Object $object -Names @("finalizer_phase", "pr_finalizer_phase", "finalizer_status") -Default ""
    if (-not [string]::IsNullOrWhiteSpace($phase)) { return $phase }
    if ($object -and $object.PSObject.Properties["evidence_summary"]) {
      $phase = Get-FirstValue -Object $object.evidence_summary -Names @("finalizer_phase", "pr_finalizer_phase", "finalizer_status") -Default ""
      if (-not [string]::IsNullOrWhiteSpace($phase)) { return $phase }
    }
  }
  return "-"
}

function Get-PrDisplayState {
  param($Step, $Task)
  $merged = $false
  $draft = $false
  $state = "-"
  foreach ($object in @($Step, $Task, $(if ($Task -and $Task.PSObject.Properties["result"]) { $Task.result } else { $null }))) {
    if ($object -and $object.PSObject.Properties["merged"] -and $object.merged -eq $true) { $merged = $true }
    if ($object -and $object.PSObject.Properties["is_draft"] -and $object.is_draft -eq $true) { $draft = $true }
    if ($object -and $object.PSObject.Properties["isDraft"] -and $object.isDraft -eq $true) { $draft = $true }
    $candidate = Get-FirstValue -Object $object -Names @("pr_state", "state", "github_pr_state") -Default ""
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $state = $candidate }
    if ($object -and $object.PSObject.Properties["evidence_summary"]) {
      $candidate = Get-FirstValue -Object $object.evidence_summary -Names @("pr_state", "github_pr_state") -Default ""
      if (-not [string]::IsNullOrWhiteSpace($candidate)) { $state = $candidate }
    }
  }
  if ($merged) { return "merged" }
  if ($draft) { return "draft" }
  if ($state -match "(?i)open|ready") { return "ready" }
  return $state
}

function Get-StepDisplay {
  param($Step, $Task = $null, [bool]$Current = $false, [bool]$Historical = $false)
  $taskId = if ($Task -and $Task.task_id) { [string]$Task.task_id } elseif ($Step -and @($Step.linked_task_ids).Count -gt 0) { [string]@($Step.linked_task_ids)[0] } else { "-" }
  $prUrl = if ($Step -and @($Step.linked_pr_urls).Count -gt 0) { [string]@($Step.linked_pr_urls)[0] } elseif ($Task -and $Task.pr_url) { [string]$Task.pr_url } else { "-" }
  $prNumber = Get-PrNumber -Url $prUrl
  [pscustomobject]@{
    goal_id = if ($Step) { [string]$Step.goal_id } else { "-" }
    title = if ($Step) { [string]$Step.title } else { "-" }
    status = if ($Step) { [string]$Step.status } else { "-" }
    task_id = $taskId
    pr_url = $prUrl
    pr_number = $prNumber
    pr_state = Get-PrDisplayState -Step $Step -Task $Task
    ci_status = Get-CiStatus -Step $Step -Task $Task
    evidence_status = Get-EvidenceStatus -Step $Step -Task $Task
    finalizer_phase = Get-FinalizerPhase -Step $Step -Task $Task
    scope = if ($Historical) { "historical" } elseif ($Current) { "current" } else { "queue" }
  }
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
    [pscustomobject]@{
      order = 1
      campaign_step_id = "$CampaignId`:super-189-ci-guardian-pr-finalizer-hardening"
      goal_id = "super-189-ci-guardian-pr-finalizer-hardening"
      title = "CI Guardian and PR Finalizer Hardening"
      status = "completed"
      linked_task_ids = @("campaign-step-super-189")
      linked_pr_urls = @("https://github.com/JerrySkywalker/skybridge-agent-hub/pull/99")
      evidence_summary = @{ recovered = $true; ci_status = "passed"; pr_state = "merged"; finalizer_phase = "evidence_repaired" }
    },
    [pscustomobject]@{
      order = 2
      campaign_step_id = "$CampaignId`:super-190-campaign-run-report-evidence-ledger"
      goal_id = "super-190-campaign-run-report-evidence-ledger"
      title = "Campaign Run Report and Evidence Ledger"
      status = "ready"
      linked_task_ids = @()
      linked_pr_urls = @()
    },
    [pscustomobject]@{ order = 3; goal_id = "super-191-readonly-operator-dashboard"; title = "Read-only Operator Dashboard"; status = "pending"; linked_task_ids = @(); linked_pr_urls = @() }
  )
  $states = @(
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null },
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null },
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null },
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null },
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null },
    @{ runner = "idle"; hold = "-"; gate = "ready"; warning = $null }
  )
  $state = $states[[Math]::Min($FrameIndex, $states.Count - 1)]
  [pscustomobject]@{
    ok = $true
    demo = $true
    api_base = "demo"
    project_id = $ProjectId
    token_printed = $false
    fetched_at = (Get-Date)
    warning = $state.warning
    project = [pscustomobject]@{ control = "paused"; active_tasks = 0; stale_leases = 0; stale_locks = 0 }
    worker = [pscustomobject]@{ worker_id = "laptop-zenbookduo"; status = "online"; last_seen = "now"; current_task_id = $null }
    campaign = [pscustomobject]@{ campaign_id = $CampaignId; status = "paused"; current_step_id = "$CampaignId`:super-190-campaign-run-report-evidence-ledger" }
    runner = [pscustomobject]@{ status = $state.runner; classification = "historical_warning"; hold_reason = $state.hold; current_step_id = "$CampaignId`:super-189-ci-guardian-pr-finalizer-hardening"; audit_log = @(
      [pscustomobject]@{ at = "2026-06-01T10:34:01Z"; decision = "runner.failed"; step_id = "super-189"; reason = "historical Goal 189 failure recovered by PR #99"; scope = "historical" },
      [pscustomobject]@{ at = "2026-06-02T02:12:00Z"; decision = "evidence.recovered"; step_id = "super-189"; reason = "PR #99 merged, CI passed"; scope = "historical" },
      [pscustomobject]@{ at = "2026-06-02T02:20:00Z"; decision = "campaign.advanced"; step_id = "super-190"; reason = "Goal 190 ready/current; not executed"; scope = "current" }
    ) }
    steps = $steps
    previous_step = Get-StepDisplay -Step $steps[0] -Historical $true
    current_step = [pscustomobject]@{
      index = 2
      total = 12
      goal_id = $steps[1].goal_id
      title = $steps[1].title
      status = $steps[1].status
      task_id = "-"
      pr = "-"
      pr_url = "-"
      pr_number = "-"
      pr_state = "-"
      checks = "-"
      ci_status = "-"
      evidence = "not_started"
      evidence_status = "not_started"
      finalizer_phase = "-"
      gate = $state.gate
    }
  }
}

function Get-WatchSnapshot {
  if ($FixtureFile) {
    return (Get-Content -Raw -LiteralPath $FixtureFile | ConvertFrom-Json)
  }
  if ($env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS) {
    Start-Sleep -Milliseconds ([int]$env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS)
  }
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
  $previous = @($steps | Where-Object { [int]$_.order -lt [int]$current.order } | Sort-Object order | Select-Object -Last 1)[0]
  $index = if ($current) { [int]$current.order } else { 0 }
  $currentTask = $null
  $previousTask = $null
  if ($current -and @($current.linked_task_ids).Count -gt 0) {
    try {
      $taskStatus = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-TaskId", [string]@($current.linked_task_ids)[0], "-Json", "-ColorMode", "Never"))
      $currentTask = @($taskStatus.tasks)[0]
    } catch {}
  }
  if ($previous -and @($previous.linked_task_ids).Count -gt 0) {
    try {
      $taskStatus = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-TaskId", [string]@($previous.linked_task_ids)[0], "-Json", "-ColorMode", "Never"))
      $previousTask = @($taskStatus.tasks)[0]
    } catch {}
  }
  $currentDisplay = Get-StepDisplay -Step $current -Task $currentTask -Current $true
  $previousDisplay = if ($previous) { Get-StepDisplay -Step $previous -Task $previousTask -Historical $true } else { $null }
  $runnerClassification = if ($runner.runner_state_classification) { [string]$runner.runner_state_classification } else { "current" }
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
      classification = $runnerClassification
      current_step_id = if ($runner.runner_state.current_step_id) { [string]$runner.runner_state.current_step_id } else { "-" }
      hold_reason = if ($runner.runner_state.hold_reason) { [string]$runner.runner_state.hold_reason } else { "-" }
      audit_log = @($runner.runner_state.audit_log)
    }
    steps = $steps
    previous_step = $previousDisplay
    current_step = [pscustomobject]@{
      index = $index
      total = @($steps).Count
      goal_id = $currentDisplay.goal_id
      title = $currentDisplay.title
      status = $currentDisplay.status
      task_id = $currentDisplay.task_id
      pr = $currentDisplay.pr_number
      pr_url = $currentDisplay.pr_url
      pr_number = $currentDisplay.pr_number
      pr_state = $currentDisplay.pr_state
      checks = $currentDisplay.ci_status
      ci_status = $currentDisplay.ci_status
      evidence = $currentDisplay.evidence_status
      evidence_status = $currentDisplay.evidence_status
      finalizer_phase = $currentDisplay.finalizer_phase
      gate = if ($campaign.gate.decision) { [string]$campaign.gate.decision } else { "-" }
    }
  }
}

if ($SnapshotJson) {
  if ($env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL -and $SnapshotFrameIndex -ge 1) {
    throw "simulated poll failure"
  }
  if ($env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS) {
    Start-Sleep -Milliseconds ([int]$env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS)
  }
  $snapshot = if ($Demo) { Get-DemoFrame -FrameIndex ($SnapshotFrameIndex % [Math]::Max(1, $Frames)) } else { Get-WatchSnapshot }
  $snapshot | ConvertTo-Json -Depth 80 -Compress
  exit 0
}

function New-PendingSnapshot {
  param([string]$Warning = $null)
  [pscustomobject]@{
    ok = $false
    demo = [bool]$Demo
    api_base = if ($Demo) { "demo" } else { $ApiBase }
    project_id = $ProjectId
    token_printed = $false
    fetched_at = $null
    warning = $Warning
    project = [pscustomobject]@{ control = "polling"; active_tasks = 0; stale_leases = 0; stale_locks = 0 }
    worker = [pscustomobject]@{ worker_id = "laptop-zenbookduo"; status = "unknown"; current_task_id = $null }
    campaign = [pscustomobject]@{ campaign_id = $CampaignId; status = "unknown"; current_step_id = "-" }
    runner = [pscustomobject]@{ status = "polling"; classification = "current"; current_step_id = "-"; hold_reason = "-"; audit_log = @() }
    steps = @()
    previous_step = $null
    current_step = [pscustomobject]@{
      index = 0
      total = 0
      goal_id = "-"
      title = "Polling remote state"
      status = "polling"
      task_id = "-"
      pr = "-"
      pr_url = "-"
      pr_number = "-"
      pr_state = "-"
      checks = "-"
      ci_status = "-"
      evidence = "-"
      evidence_status = "-"
      finalizer_phase = "-"
      gate = "-"
    }
  }
}

function Start-SnapshotPoll {
  param([int]$FrameIndex)
  if ($Demo) {
    $delayMs = if ($env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS) { [int]$env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS } else { 0 }
    return Start-ThreadJob -ScriptBlock {
      param([int]$DelayMilliseconds, [int]$FrameIndex, [int]$FrameCount, [string]$ProjectId, [string]$CampaignId)
      if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
      $steps = @(
        [pscustomobject]@{ order = 1; campaign_step_id = "$CampaignId`:super-189-ci-guardian-pr-finalizer-hardening"; goal_id = "super-189-ci-guardian-pr-finalizer-hardening"; title = "CI Guardian and PR Finalizer Hardening"; status = "completed"; linked_task_ids = @("campaign-step-super-189"); linked_pr_urls = @("https://github.com/JerrySkywalker/skybridge-agent-hub/pull/99"); evidence_summary = @{ recovered = $true; ci_status = "passed"; pr_state = "merged"; finalizer_phase = "evidence_repaired" } },
        [pscustomobject]@{ order = 2; campaign_step_id = "$CampaignId`:super-190-campaign-run-report-evidence-ledger"; goal_id = "super-190-campaign-run-report-evidence-ledger"; title = "Campaign Run Report and Evidence Ledger"; status = "ready"; linked_task_ids = @(); linked_pr_urls = @() },
        [pscustomobject]@{ order = 3; goal_id = "super-191-readonly-operator-dashboard"; title = "Read-only Operator Dashboard"; status = "pending"; linked_task_ids = @(); linked_pr_urls = @() }
      )
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
        campaign = [pscustomobject]@{ campaign_id = $CampaignId; status = "paused"; current_step_id = "$CampaignId`:super-190-campaign-run-report-evidence-ledger" }
        runner = [pscustomobject]@{ status = "idle"; classification = "historical_warning"; hold_reason = "-"; current_step_id = "$CampaignId`:super-189-ci-guardian-pr-finalizer-hardening"; audit_log = @(
          [pscustomobject]@{ at = "2026-06-01T10:34:01Z"; decision = "runner.failed"; step_id = "super-189"; reason = "historical Goal 189 failure recovered by PR #99"; scope = "historical" },
          [pscustomobject]@{ at = "2026-06-02T02:12:00Z"; decision = "evidence.recovered"; step_id = "super-189"; reason = "PR #99 merged, CI passed"; scope = "historical" },
          [pscustomobject]@{ at = "2026-06-02T02:20:00Z"; decision = "campaign.advanced"; step_id = "super-190"; reason = "Goal 190 ready/current; not executed"; scope = "current" }
        ) }
        steps = $steps
        previous_step = [pscustomobject]@{ goal_id = "super-189-ci-guardian-pr-finalizer-hardening"; title = "CI Guardian and PR Finalizer Hardening"; status = "completed"; task_id = "campaign-step-super-189"; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/99"; pr_number = "#99"; pr_state = "merged"; ci_status = "passed"; evidence_status = "recovered"; finalizer_phase = "evidence_repaired"; scope = "historical" }
        current_step = [pscustomobject]@{ index = 2; total = 12; goal_id = "super-190-campaign-run-report-evidence-ledger"; title = "Campaign Run Report and Evidence Ledger"; status = "ready"; task_id = "-"; pr = "-"; pr_url = "-"; pr_number = "-"; pr_state = "-"; checks = "-"; ci_status = "-"; evidence = "not_started"; evidence_status = "not_started"; finalizer_phase = "-"; gate = "ready" }
      } | ConvertTo-Json -Depth 80 -Compress
    } -ArgumentList $delayMs, $FrameIndex, $Frames, $ProjectId, $CampaignId
  }
  $args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
    "-ApiBase", $ApiBase,
    "-ProjectId", $ProjectId,
    "-CampaignId", $CampaignId,
    "-PollIntervalSeconds", [string]$PollIntervalSeconds,
    "-RenderIntervalMilliseconds", [string]$RenderIntervalMilliseconds,
    "-SnapshotJson",
    "-SnapshotFrameIndex", [string]$FrameIndex,
    "-ColorMode", "Never")
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if (-not [string]::IsNullOrWhiteSpace($FixtureFile)) { $args += @("-FixtureFile", $FixtureFile) }
  if ($Demo) { $args += @("-Demo", "-Frames", [string]$Frames) }
  return Start-ThreadJob -ScriptBlock {
    param([string[]]$ChildArgs)
    & pwsh @ChildArgs
  } -ArgumentList (,$args)
}

function Receive-SnapshotPoll {
  param($Job)
  $output = @(Receive-Job -Job $Job -ErrorAction SilentlyContinue)
  $errorOutput = @($Job.ChildJobs | ForEach-Object { $_.Error } | ForEach-Object { [string]$_ })
  Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
  if ($Job.State -ne "Completed") {
    $message = if ($errorOutput.Count -gt 0) { $errorOutput -join "`n" } else { "snapshot poll $($Job.State.ToString().ToLowerInvariant())" }
    throw $message
  }
  $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
  if ([string]::IsNullOrWhiteSpace($text)) { throw "snapshot poll returned no JSON" }
  return ($text | ConvertFrom-Json)
}

function Format-StepLine {
  param($Step, [int]$Total, [bool]$Current)
  $marker = if ($Current) { ">" } else { " " }
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
  $lines.Add("--------------------------------------------------------------------------------------") | Out-Null
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
  $runnerClass = if ($Snapshot.runner.classification) { [string]$Snapshot.runner.classification } else { "current" }
  if ($runnerClass -match "historical") {
    $lines.Add((Colorize (" History     old runner state={0}; not a current blocker" -f $runnerClass) "yellow")) | Out-Null
  }
  if ($script:EffectiveLayout -eq "Compact") {
    $pr = if ($Snapshot.current_step.pr_number -and $Snapshot.current_step.pr_number -ne "-") { "$($Snapshot.current_step.pr_number) $($Snapshot.current_step.pr_state)" } else { "-" }
    $lines.Add((" Current     {0}  {1}  task={2} pr={3} ci={4} evidence={5} gate={6}" -f $Snapshot.current_step.goal_id, $Snapshot.current_step.status, $Snapshot.current_step.task_id, $pr, $Snapshot.current_step.ci_status, $Snapshot.current_step.evidence_status, $Snapshot.current_step.gate)) | Out-Null
    if ($Snapshot.previous_step) {
      $lines.Add((" Previous    {0}  {1}  pr={2} {3} ci={4} evidence={5}" -f $Snapshot.previous_step.goal_id, $Snapshot.previous_step.status, $Snapshot.previous_step.pr_number, $Snapshot.previous_step.pr_state, $Snapshot.previous_step.ci_status, $Snapshot.previous_step.evidence_status)) | Out-Null
    }
    return ($lines -join "`n")
  }
  $lines.Add("") | Out-Null
  $lines.Add("Current Step") | Out-Null
  $lines.Add(("   {0:00}/{1:00}  {2}" -f $Snapshot.current_step.index, $Snapshot.current_step.total, $Snapshot.current_step.title)) | Out-Null
  $lines.Add(("  goal:     {0}" -f $Snapshot.current_step.goal_id)) | Out-Null
  $lines.Add(("  task:     {0}" -f $Snapshot.current_step.task_id)) | Out-Null
  $lines.Add(("  PR:       {0}  {1}  {2}" -f $Snapshot.current_step.pr_number, $Snapshot.current_step.pr_state, $Snapshot.current_step.pr_url)) | Out-Null
  $lines.Add(("  CI:       {0}" -f $Snapshot.current_step.ci_status)) | Out-Null
  $lines.Add(("  evidence: {0}" -f $Snapshot.current_step.evidence_status)) | Out-Null
  $lines.Add(("  finalizer:{0}" -f $Snapshot.current_step.finalizer_phase)) | Out-Null
  $lines.Add(("  gate:     {0}" -f $Snapshot.current_step.gate)) | Out-Null
  $lines.Add(("  hold:     {0}" -f $Snapshot.runner.hold_reason)) | Out-Null
  if ($Snapshot.previous_step) {
    $lines.Add("") | Out-Null
    $lines.Add("Previous Step") | Out-Null
    $lines.Add(("  goal:     {0}  {1}" -f $Snapshot.previous_step.goal_id, $Snapshot.previous_step.status)) | Out-Null
    $lines.Add(("  task:     {0}" -f $Snapshot.previous_step.task_id)) | Out-Null
    $lines.Add(("  PR:       {0}  {1}  {2}" -f $Snapshot.previous_step.pr_number, $Snapshot.previous_step.pr_state, $Snapshot.previous_step.pr_url)) | Out-Null
    $lines.Add(("  CI:       {0}" -f $Snapshot.previous_step.ci_status)) | Out-Null
    $lines.Add(("  evidence: {0}" -f $Snapshot.previous_step.evidence_status)) | Out-Null
    $lines.Add(("  finalizer:{0}" -f $Snapshot.previous_step.finalizer_phase)) | Out-Null
  }
  $lines.Add("") | Out-Null
  $lines.Add("Queue") | Out-Null
  $window = if ($script:EffectiveLayout -eq "Debug") { 6 } else { 3 }
  foreach ($step in @($Snapshot.steps | Sort-Object order | Where-Object { [Math]::Abs([int]$_.order - [int]$Snapshot.current_step.index) -le $window })) {
    $lines.Add((Format-StepLine -Step $step -Total $Snapshot.current_step.total -Current ([int]$step.order -eq [int]$Snapshot.current_step.index))) | Out-Null
  }
  if ($script:EffectiveLayout -eq "Debug") {
    $lines.Add("") | Out-Null
    $lines.Add("Debug Fusion") | Out-Null
    $lines.Add(("  layout:              {0}" -f $script:EffectiveLayout)) | Out-Null
    $lines.Add(("  campaign_current:    {0}" -f $Snapshot.campaign.current_step_id)) | Out-Null
    $lines.Add(("  runner_current:      {0}" -f $Snapshot.runner.current_step_id)) | Out-Null
    $lines.Add(("  runner_class:        {0}" -f $runnerClass)) | Out-Null
    $lines.Add(("  active_tasks:        {0}" -f $Snapshot.project.active_tasks)) | Out-Null
    $lines.Add(("  stale_leases:        {0}" -f $Snapshot.project.stale_leases)) | Out-Null
    $lines.Add(("  stale_locks:         {0}" -f $Snapshot.project.stale_locks)) | Out-Null
  }
  if ($ShowEvents -or $script:EffectiveLayout -eq "Debug" -or @($Snapshot.runner.audit_log).Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("Recent Events") | Out-Null
    $events = @($Snapshot.runner.audit_log | Select-Object -Last $EventLimit)
    if ($events.Count -eq 0) { $lines.Add("  -") | Out-Null }
    foreach ($event in $events) {
      $when = if ($event.at) { ([string]$event.at) } else { "-" }
      if ($when.Length -gt 8) { $when = $when.Substring(0, [Math]::Min(19, $when.Length)) }
      $scope = if ($event.scope) { [string]$event.scope } else { "historical" }
      $lines.Add(("  {0,-19}  {1,-10} {2}  {3}" -f $when, $scope, $event.decision, $event.reason)) | Out-Null
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
$pollJob = $null
$effectiveOnce = [bool]($Once -or $Json)
$effectiveMaxFrames = if ($MaxFrames -gt 0) { $MaxFrames } elseif ($Demo -and $Frames -gt 0) { $Frames } else { 0 }
try {
  do {
    $spinner = $SpinnerFrames[$frameIndex % $SpinnerFrames.Count]
    $shouldPoll = $null -eq $snapshot -or ((Get-Date) - $lastPoll).TotalSeconds -ge $PollIntervalSeconds
    try {
      if ($effectiveOnce) {
        if ($env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL -and $frameIndex -ge 1) { throw "simulated poll failure" }
        $snapshot = if ($Demo) { Get-DemoFrame -FrameIndex ($frameIndex % [Math]::Max(1, $Frames)) } else { Get-WatchSnapshot }
        $lastPoll = Get-Date
      } else {
        if ($Demo -and -not $env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS) {
          if ($shouldPoll) {
            if ($env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL -and $frameIndex -ge 1) { throw "simulated poll failure" }
            $snapshot = Get-DemoFrame -FrameIndex ($frameIndex % [Math]::Max(1, $Frames))
            $lastPoll = Get-Date
          }
        } elseif ($null -ne $pollJob -and $pollJob.State -in @("Completed", "Failed", "Stopped")) {
          try {
            $snapshot = Receive-SnapshotPoll -Job $pollJob
            $lastPoll = Get-Date
          } catch {
            if ($null -eq $snapshot) { $snapshot = New-PendingSnapshot -Warning $_.Exception.Message }
            else { $snapshot.warning = $_.Exception.Message }
          } finally {
            $pollJob = $null
          }
        }
        if ($shouldPoll -and $null -eq $pollJob) {
          $pollJob = Start-SnapshotPoll -FrameIndex $frameIndex
          $lastPoll = Get-Date
        }
        if ($null -eq $snapshot) {
          $snapshot = New-PendingSnapshot
        } elseif ($SpinnerOnlyBetweenPolls -and $snapshot.PSObject.Properties["warning"] -and $null -ne $pollJob) {
          $snapshot.warning = $null
        }
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
  if ($null -ne $pollJob) {
    Stop-Job -Job $pollJob -ErrorAction SilentlyContinue
    Remove-Job -Job $pollJob -Force -ErrorAction SilentlyContinue
  }
}
