[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [string]$GoalTitle,
  [string]$Description,
  [string]$WorkerProfile,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$MaxRounds = 1,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp",
  [ValidateSet("rule-based")]
  [string]$PlannerMode = "rule-based",
  [switch]$AllowHighRisk,
  [switch]$StopAfterPlan,
  [switch]$StopAfterProposal,
  [switch]$StopAfterConvert,
  [switch]$NoRun
)

$ErrorActionPreference = "Stop"

function Get-HashText {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
  } finally {
    $sha.Dispose()
  }
}

function New-SupervisorId {
  param([string]$Prefix)
  $now = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
  return "$Prefix-$now-$(Get-HashText "$ProjectId/$MasterGoalId/$now")"
}

function New-MasterGoalId {
  param([string]$Title)
  $slug = (($Title ?? "").ToLowerInvariant() -replace "[^a-z0-9]+", "-" -replace "^-|-$", "")
  if ([string]::IsNullOrWhiteSpace($slug)) { throw "skybridge-supervise requires -MasterGoalId or a non-empty -GoalTitle to derive one." }
  return "master-goal-$($slug.Substring(0, [Math]::Min(72, $slug.Length)))"
}

function Invoke-SupervisorJsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $(Format-SafeArguments -Arguments $Arguments)" }
  return ($output | ConvertFrom-Json)
}

function Format-SafeArguments {
  param([string[]]$Arguments)
  $safe = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    $arg = [string]$Arguments[$i]
    $safe.Add($arg) | Out-Null
    if ($arg -in @("-TokenFile", "-TokenEnvVar") -and ($i + 1) -lt $Arguments.Count) {
      $i++
      $safe.Add("<redacted>") | Out-Null
    }
  }
  return ($safe.ToArray() -join " ")
}

function Add-AuthArgs {
  param([string[]]$Arguments)
  $result = @($Arguments)
  if ($TokenEnvVar) { $result += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $result += @("-TokenFile", $TokenFile) }
  return $result
}

function Get-DisplayTaskStatus {
  param($Task)
  if ($null -eq $Task) { return $null }
  $raw = if ($Task.raw_status) { [string]$Task.raw_status } elseif ($Task.status) { [string]$Task.status } else { "unknown" }
  $evidence = $Task.evidence_summary
  $recovered = $Task.recovered -eq $true -or ($evidence -and $evidence.recovered -eq $true)
  $ci = if ($Task.ci_status) { [string]$Task.ci_status } elseif ($evidence -and $evidence.ci_status) { [string]$evidence.ci_status } else { $null }
  if ($raw -eq "failed" -and $recovered) {
    if ($ci -eq "passed_after_rerun") { return "recovered" }
    return "failed/recovered"
  }
  return $raw
}

function Select-SupervisorProposal {
  param([array]$Proposals, [switch]$AllowHighRisk)
  $proposalRows = @($Proposals)
  $duplicateKeys = @($proposalRows | Group-Object dedupe_key | Where-Object { $_.Name -and $_.Count -gt 1 } | ForEach-Object { $_.Name })
  $eligible = @($proposalRows | Where-Object {
    $_.status -notin @("converted", "rejected") -and
    ($duplicateKeys -notcontains $_.dedupe_key) -and
    (@($_.required_capabilities) -contains "codex")
  })
  $safe = @($eligible | Where-Object { $_.risk -eq "low" })
  if (@($safe).Count -gt 0) {
    $docs = @($safe | Where-Object { $_.task_type -eq "docs" })
    if (@($docs).Count -gt 0) {
      return @($docs | Sort-Object `
        @{ Expression = { if (@($_.expected_files | Where-Object { $_ -like "docs/dev/*" }).Count -gt 0) { 0 } else { 1 } } }, `
        @{ Expression = { if ([string]$_.dedupe_key -match "-record$") { 0 } else { 1 } } }, `
        @{ Expression = { [string]$_.dedupe_key } })[0]
    }
    return @($safe)[0]
  }
  if ($AllowHighRisk) {
    $high = @($eligible | Where-Object { $_.risk -eq "high" })
    if (@($high).Count -gt 0) { return @($high)[0] }
  }
  return $null
}

function Get-SupervisorDecision {
  param($Status, [array]$Proposals, $SelectedProposal, $LatestTask, [switch]$AllowHighRisk)
  $control = $Status.control
  if ($control -and $control.stop_requested -eq $true) {
    return [pscustomobject]@{ decision = "ask_human"; stop_reason = "project_stop_requested"; reason = "Project control has stop_requested=true." }
  }
  $workers = @($Status.workers)
  if (@($workers | Where-Object { $_.status -eq "online" }).Count -eq 0) {
    return [pscustomobject]@{ decision = "stop_worker_unavailable"; stop_reason = "worker_unavailable"; reason = "No online worker is visible in project state." }
  }
  if ($LatestTask) {
    $display = Get-DisplayTaskStatus -Task $LatestTask
    if ($display -eq "completed" -or $display -eq "recovered") {
      return [pscustomobject]@{ decision = "continue"; stop_reason = $null; reason = "Latest task is $display." }
    }
    if ($display -eq "failed" -or $display -eq "failed/recovered") {
      return [pscustomobject]@{ decision = "stop_task_failed"; stop_reason = "task_failed"; reason = "Latest task status is $display." }
    }
  }
  if (-not $SelectedProposal) {
    $hasHigh = @($Proposals | Where-Object { $_.risk -eq "high" -and $_.status -notin @("converted", "rejected") }).Count -gt 0
    if ($hasHigh -and -not $AllowHighRisk) {
      return [pscustomobject]@{ decision = "ask_human"; stop_reason = "high_risk_requires_review"; reason = "Only high-risk proposals remain and -AllowHighRisk was not supplied." }
    }
    return [pscustomobject]@{ decision = "stop_no_safe_proposal"; stop_reason = "no_safe_proposal"; reason = "No low-risk codex proposal is available." }
  }
  return [pscustomobject]@{ decision = "continue"; stop_reason = $null; reason = "Selected one bounded proposal." }
}

function Write-SupervisorResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 60 -Compress
    return
  }
  "Supervisor:  $($Result.supervisor_run.supervisor_run_id)"
  "Mode:        $($Result.supervisor_run.mode)"
  "Project:     $($Result.project_id)"
  "MasterGoal:  $($Result.master_goal_id)"
  "Status:      $($Result.supervisor_run.status)"
  "StopReason:  $(if ($Result.supervisor_run.stop_reason) { $Result.supervisor_run.stop_reason } else { '-' })"
  "Rounds:      $(@($Result.rounds).Count)/$($Result.supervisor_run.max_rounds)"
  foreach ($round in @($Result.rounds)) {
    "  round $($round.round_index): $($round.action) decision=$($round.decision.decision) proposal=$(if ($round.selected_proposal_id) { $round.selected_proposal_id } else { '-' }) task=$(if ($round.selected_task_id) { $round.selected_task_id } else { '-' })"
    "    reason: $($round.decision.reason)"
  }
  "TokenPrinted: false"
}

if ($MaxRounds -lt 1) { throw "skybridge-supervise requires -MaxRounds greater than zero." }
if (-not $GoalTitle) { throw "skybridge-supervise requires -GoalTitle." }
if (-not $MasterGoalId) { $MasterGoalId = New-MasterGoalId -Title $GoalTitle }
if ($Apply -and $DryRun) { throw "Use either -Apply or -DryRun, not both." }
if ($Apply -and -not $NoRun -and -not $WorkerProfile) { throw "skybridge-supervise -Apply requires -WorkerProfile unless -NoRun is supplied." }

$effectiveDryRun = $DryRun -or -not $Apply
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$now = (Get-Date).ToUniversalTime().ToString("o")
$run = [pscustomobject]@{
  supervisor_run_id = New-SupervisorId -Prefix "supervisor-run"
  project_id = $ProjectId
  master_goal_id = $MasterGoalId
  mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
  max_rounds = $MaxRounds
  current_round = 0
  status = "planned"
  stop_reason = $null
  created_at = $now
  updated_at = $now
}

$rounds = New-Object System.Collections.Generic.List[object]
$latestTask = $null
$supervisorError = $null

try {
  $run.status = "running"
  for ($roundIndex = 1; $roundIndex -le $MaxRounds; $roundIndex++) {
    $run.current_round = $roundIndex
    $statusArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ShowAll", "-Json", "-OutputFile", (Join-Path $OutputDir "supervisor-status-round-$roundIndex.json"))
    $status = Invoke-SupervisorJsonScript -Arguments $statusArgs

    $planArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-plan.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-Title", $GoalTitle, "-PlannerMode", $PlannerMode, "-Json", "-OutputFile", (Join-Path $OutputDir "supervisor-plan-round-$roundIndex.json"))
    if ($Description) { $planArgs += @("-Description", $Description) }
    if ($effectiveDryRun) { $planArgs += "-DryRun" } else { $planArgs += "-Apply" }
    $plan = Invoke-SupervisorJsonScript -Arguments $planArgs

    $proposals = @($plan.proposals)
    if (-not $effectiveDryRun) {
      $listArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "list", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-Json")
      $proposals = @((Invoke-SupervisorJsonScript -Arguments $listArgs).proposals)
    }

    $selected = Select-SupervisorProposal -Proposals $proposals -AllowHighRisk:$AllowHighRisk
    $decision = Get-SupervisorDecision -Status $status -Proposals $proposals -SelectedProposal $selected -LatestTask $latestTask -AllowHighRisk:$AllowHighRisk
    $round = [pscustomobject]@{
      round_index = $roundIndex
      observed_state_summary = [pscustomobject]@{
        control_state = $status.control.state
        stop_requested = $status.control.stop_requested
        workers_online = @($status.workers | Where-Object { $_.status -eq "online" }).Count
        task_count = @($status.tasks).Count
        proposal_count = @($proposals).Count
      }
      selected_proposal_id = if ($selected) { $selected.proposal_id } else { $null }
      selected_task_id = $null
      action = "plan"
      decision = $decision
      decision_reason = $decision.reason
      pr_url = $null
      ci_status = $null
      task_status = $null
      evidence_status = $null
      proposal = $selected
      task = $null
      run_once = $null
    }

    if ($StopAfterPlan) {
      $round.action = "stop"
      $round.decision = [pscustomobject]@{ decision = "stop_completed"; stop_reason = "stop_after_plan"; reason = "Stopped after planning by operator flag." }
      $rounds.Add($round)
      $run.status = "stopped"; $run.stop_reason = "stop_after_plan"
      break
    }

    if ($decision.decision -ne "continue") {
      $round.action = if ($decision.decision -eq "ask_human") { "ask_human" } else { "stop" }
      $rounds.Add($round)
      $run.status = if ($decision.decision -eq "ask_human") { "blocked" } else { "stopped" }
      $run.stop_reason = $decision.stop_reason
      break
    }

    if ($StopAfterProposal) {
      $round.action = "stop"
      $round.decision = [pscustomobject]@{ decision = "stop_completed"; stop_reason = "stop_after_proposal"; reason = "Stopped after proposal selection by operator flag." }
      $rounds.Add($round)
      $run.status = "stopped"; $run.stop_reason = "stop_after_proposal"
      break
    }

    if ($effectiveDryRun) {
      $taskId = "task_$($selected.proposal_id)"
      $round.selected_task_id = $taskId
      $round.action = "convert"
      $round.task = [pscustomobject]@{
        task_id = $taskId
        project_id = $ProjectId
        title = $selected.title
        risk = $selected.risk
        task_type = $selected.task_type
        expected_files = @($selected.expected_files)
      }
      $round.run_once = [pscustomobject]@{
        would_run = $true
        command = "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 -ApiBase `"$ApiBase`" -ProjectId `"$ProjectId`" -TaskId `"$taskId`" -GoalId `"$MasterGoalId`" -NoSubmit -Apply -WorkerProfile `"$WorkerProfile`""
      }
      $rounds.Add($round)
      $run.status = "completed"; $run.stop_reason = "dry_run_preview_complete"
      break
    }

    $acceptArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "accept", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $selected.proposal_id, "-Apply", "-Json")
    Invoke-SupervisorJsonScript -Arguments $acceptArgs | Out-Null
    $convertArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "convert", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $selected.proposal_id, "-Apply", "-Json")
    if ($AllowHighRisk) { $convertArgs += "-AllowHighRisk" }
    $converted = Invoke-SupervisorJsonScript -Arguments $convertArgs
    $round.action = "convert"
    $round.selected_task_id = $converted.task.task_id
    $round.task = $converted.task

    if ($StopAfterConvert -or $NoRun) {
      $round.decision = [pscustomobject]@{ decision = "stop_completed"; stop_reason = if ($NoRun) { "no_run" } else { "stop_after_convert" }; reason = "Converted one proposal and skipped execution by operator flag." }
      $rounds.Add($round)
      $run.status = "completed"; $run.stop_reason = $round.decision.stop_reason
      break
    }

    $runArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-WorkerProfile", $WorkerProfile, "-TaskId", $converted.task.task_id, "-GoalId", $MasterGoalId, "-NoSubmit", "-Apply", "-Json", "-OutputDir", $OutputDir)
    $runOnce = Invoke-SupervisorJsonScript -Arguments $runArgs
    $round.action = "run_once"
    $round.run_once = $runOnce

    $inspectArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TaskId", $converted.task.task_id, "-Json")
    $inspect = Invoke-SupervisorJsonScript -Arguments $inspectArgs
    $latestTask = @($inspect.tasks)[0]
    $round.task_status = Get-DisplayTaskStatus -Task $latestTask
    $round.pr_url = $latestTask.pr_url
    $round.ci_status = $latestTask.ci_status
    $round.evidence_status = $latestTask.evidence
    $rounds.Add($round)

    $afterDecision = Get-SupervisorDecision -Status $status -Proposals $proposals -SelectedProposal $selected -LatestTask $latestTask -AllowHighRisk:$AllowHighRisk
    if ($afterDecision.decision -ne "continue") {
      $run.status = if ($afterDecision.decision -eq "ask_human") { "blocked" } elseif ($afterDecision.decision -eq "stop_task_failed") { "failed" } else { "stopped" }
      $run.stop_reason = $afterDecision.stop_reason
      break
    }
    if ($roundIndex -eq $MaxRounds) {
      $run.status = "completed"
      $run.stop_reason = "max_rounds_reached"
    }
  }
} catch {
  $supervisorError = $_
  $run.status = "failed"
  $run.stop_reason = "supervisor_error"
} finally {
  if (-not $effectiveDryRun) {
    try {
      $pauseArgs = Add-AuthArgs @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
      Invoke-SupervisorJsonScript -Arguments $pauseArgs | Out-Null
    } catch {}
  }
  $run.updated_at = (Get-Date).ToUniversalTime().ToString("o")
}

if ($run.status -eq "running") {
  $run.status = "completed"
  $run.stop_reason = "max_rounds_reached"
}

$result = [pscustomobject]@{
  ok = ($null -eq $supervisorError)
  api_base = $ApiBase
  project_id = $ProjectId
  master_goal_id = $MasterGoalId
  token_printed = $false
  supervisor_run = $run
  rounds = @($rounds.ToArray())
  error = if ($supervisorError) { [string]$supervisorError.Exception.Message } else { $null }
}

$result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $OutputDir "skybridge-supervise-result.json") -Encoding UTF8
Write-SupervisorResult -Result $result
if ($supervisorError) { exit 1 }
