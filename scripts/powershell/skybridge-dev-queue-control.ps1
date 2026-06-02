[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("preflight", "watch", "start-one", "start-all", "safe-pause", "emergency-stop", "resume", "report", "unlock-stale-runner")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$GoalPackDir = "goals/dev-queue-189-200",
  [string]$WorkerProfile = "$HOME\.skybridge\worker.laptop-zenbookduo.json",
  [string]$HermesEnvFile = "$HOME\.skybridge\hermes.env.ps1",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$TokenEnvVar,
  [int]$MaxRuntimeMinutes = 240,
  [switch]$Apply,
  [switch]$DryRun,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason,
  [ValidateSet("Auto", "Always", "Never")]
  [string]$ColorMode = "Auto",
  [int]$PollIntervalSeconds = 5,
  [int]$RenderIntervalMilliseconds = 250,
  [switch]$SpinnerOnlyBetweenPolls,
  [int]$MaxFrames = 0,
  [switch]$Once,
  [switch]$NoClear,
  [switch]$Compact
)

$ErrorActionPreference = "Stop"

function Get-LastJsonPayloadFromOutput {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  $lines = @($Text -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  for ($lineIndex = $lines.Count - 1; $lineIndex -ge 0; $lineIndex--) {
    $candidate = ([string]$lines[$lineIndex]).Trim()
    if (-not ($candidate.StartsWith("{") -or $candidate.StartsWith("["))) { continue }
    try {
      $null = $candidate | ConvertFrom-Json -ErrorAction Stop
      $prefixLines = if ($lineIndex -gt 0) { @($lines | Select-Object -First $lineIndex) } else { @() }
      return [pscustomobject]@{
        json = $candidate
        prefix = ($prefixLines -join "`n")
        suffix = ""
      }
    } catch {
    }
  }
  $starts = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $Text.Length; $i++) {
    if ($Text[$i] -eq "{" -or $Text[$i] -eq "[") { $starts.Add($i) | Out-Null }
  }
  foreach ($RequireCleanSuffix in @($true, $false)) {
    for ($s = $starts.Count - 1; $s -ge 0; $s--) {
      $start = $starts[$s]
      for ($end = $Text.Length; $end -gt $start; $end--) {
        $suffix = $Text.Substring($end)
        if ($RequireCleanSuffix -and -not [string]::IsNullOrWhiteSpace($suffix)) { continue }
        $candidate = $Text.Substring($start, $end - $start).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
          $null = $candidate | ConvertFrom-Json -ErrorAction Stop
          return [pscustomobject]@{
            json = $candidate
            prefix = $Text.Substring(0, $start)
            suffix = $suffix
          }
        } catch {
        }
      }
    }
  }
  return $null
}

function Format-ChildOutputDiagnostic {
  param([string]$Text)
  $safe = [string]$Text
  $safe = $safe -replace "(?i)(token|authorization|api[_-]?key)(\s*[:=]\s*)\S+", '$1$2[REDACTED]'
  $lines = @($safe -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -le 6) { return ($lines -join "`n") }
  return (@($lines | Select-Object -First 3) + @("...") + @($lines | Select-Object -Last 3)) -join "`n"
}

function ConvertFrom-MixedJsonOutput {
  param([object[]]$Output)
  $text = ($Output | ForEach-Object { [string]$_ }) -join "`n"
  try {
    $value = $text | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
      value = $value
      parse_mode = "whole_json"
      non_json_prefix_present = $false
      non_json_prefix = ""
      non_json_suffix = ""
    }
  } catch {
    $payload = Get-LastJsonPayloadFromOutput -Text $text
    if ($null -eq $payload) {
      $diagnostic = Format-ChildOutputDiagnostic -Text $text
      throw "Child command did not emit parseable JSON. Output excerpt:`n$diagnostic"
    }
    $value = $payload.json | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
      value = $value
      parse_mode = "extracted_json"
      non_json_prefix_present = -not [string]::IsNullOrWhiteSpace($payload.prefix)
      non_json_prefix = (Format-ChildOutputDiagnostic -Text $payload.prefix)
      non_json_suffix = (Format-ChildOutputDiagnostic -Text $payload.suffix)
    }
  }
}

function Invoke-JsonScript {
  param([string[]]$Arguments, [switch]$IncludeParseMetadata)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  if ($env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX) {
    $output = @($env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX) + @($output)
  }
  $parsed = ConvertFrom-MixedJsonOutput -Output $output
  if ($IncludeParseMetadata) { return $parsed }
  return $parsed.value
}

function Invoke-TextScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  return ($output -join "`n")
}

function Get-TokenArgs {
  $args = @()
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  return $args
}

function Test-GitPreflight {
  $branch = (git branch --show-current).Trim()
  $dirty = -not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim())
  $mainSync = "unknown"
  try {
    git fetch --quiet origin main *> $null
    $mainSync = ((git rev-parse main).Trim() -eq (git rev-parse origin/main).Trim())
  } catch {
    $mainSync = "unknown"
  }
  [pscustomobject]@{ branch = $branch; dirty = $dirty; main_sync = $mainSync }
}

function Write-ControlOutput {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 80 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $ProjectId"
  "Campaign:     $CampaignId"
  "OK:           $($Result.ok)"
  if ($Result.summary) { $Result.summary }
  if ($Result.instructions) { $Result.instructions }
}

function Invoke-Preflight {
  $tokenArgs = Get-TokenArgs
  $git = Test-GitPreflight
  $active = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-ActiveOnly", "-Json", "-ColorMode", "Never"))
  $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
  $campaign = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $runner = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
  $worker = $null
  if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
    $worker = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-Json")
  }
  $goal189 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
  $goal190 = @($campaign.steps | Where-Object { $_.goal_id -eq "super-190-campaign-run-report-evidence-ledger" })[0]
  $goal189Recovered = $false
  if ($goal189 -and $goal189.evidence_summary) {
    $goal189Recovered = [bool]$goal189.evidence_summary.recovered -or [string]$goal189.evidence_summary.recovery_status -in @("recovered", "completed")
  }
  $goal190LinkedTaskCount = if ($goal190) { @($goal190.linked_task_ids).Count } else { 0 }
  $goal190LinkedPrCount = if ($goal190) { @($goal190.linked_pr_urls).Count } else { 0 }
  $goal190Unexecuted = ($goal190 -and $goal190LinkedTaskCount -eq 0 -and $goal190LinkedPrCount -eq 0)
  $checks = [ordered]@{
    git_clean = -not [bool]$git.dirty
    active_tasks_zero = ([int]$active.task_summary.active -eq 0)
    stale_leases_zero = ([int]$hygiene.task_summary.stale_leases -eq 0)
    runner_lock_clear = ([string]$runner.runner_lock_status -in @("none", "released"))
    campaign_exists = ($null -ne $campaign.campaign)
    goal_189_completed = ($goal189 -and [string]$goal189.status -eq "completed")
    goal_189_recovered_or_evidence_complete = ($goal189 -and $goal189Recovered)
    goal_190_current = ($goal190 -and [string]$campaign.campaign.current_step_id -eq [string]$goal190.campaign_step_id)
    goal_190_ready = ($goal190 -and [string]$goal190.status -eq "ready")
    goal_190_unexecuted = $goal190Unexecuted
    project_paused = ([string]$active.control.state -eq "paused")
  }
  [pscustomobject]@{
    ok = -not (@($checks.GetEnumerator() | Where-Object { -not $_.Value }).Count -gt 0)
    command = "preflight"
    mode = "read"
    token_printed = $false
    git = $git
    checks = $checks
    active_tasks = [int]$active.task_summary.active
    stale_leases = [int]$hygiene.task_summary.stale_leases
    runner_lock_status = [string]$runner.runner_lock_status
    campaign_status = [string]$campaign.campaign.status
    current_step = [string]$campaign.campaign.current_step_id
    previous_step = if ($goal189) { [pscustomobject]@{ goal_id = [string]$goal189.goal_id; status = [string]$goal189.status; linked_task_ids = @($goal189.linked_task_ids); linked_pr_urls = @($goal189.linked_pr_urls); recovered = $goal189Recovered } } else { $null }
    current_step_detail = if ($goal190) { [pscustomobject]@{ goal_id = [string]$goal190.goal_id; status = [string]$goal190.status; linked_task_ids = @($goal190.linked_task_ids); linked_pr_urls = @($goal190.linked_pr_urls); unexecuted = $goal190Unexecuted } } else { $null }
    worker_status = if ($worker) { [string]$worker.remote_status } else { "unknown" }
    worker_current_task_id = if ($worker) { $worker.current_task_id } else { $null }
    next_safe_action = "Run the Pre-190 Acceptance Gate before any start-one/start-all/resume -Apply. Goal 190 must remain unexecuted until that gate passes."
    summary = "preflight active=$($active.task_summary.active) stale_leases=$($hygiene.task_summary.stale_leases) runner_lock=$($runner.runner_lock_status) current=$($campaign.campaign.current_step_id) goal190_unexecuted=$goal190Unexecuted"
  }
}

if ($Apply -and $DryRun) { throw "Use either -Apply or -DryRun, not both." }
$mode = if ($Apply) { "apply" } else { "dry-run" }
$tokenArgs = Get-TokenArgs
$result = $null

switch ($Command) {
  "preflight" {
    $result = Invoke-Preflight
  }
  "watch" {
    $watchArgs = @("-File", ".\scripts\powershell\skybridge-campaign-watch.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-CampaignId", $CampaignId, "-ColorMode", $ColorMode) + $tokenArgs
    if ($Once) { $watchArgs += "-Once" }
    if ($NoClear) { $watchArgs += "-NoClear" }
    if ($Compact) { $watchArgs += "-Compact" }
    if ($PollIntervalSeconds -gt 0) { $watchArgs += @("-PollIntervalSeconds", [string]$PollIntervalSeconds) }
    if ($RenderIntervalMilliseconds -gt 0) { $watchArgs += @("-RenderIntervalMilliseconds", [string]$RenderIntervalMilliseconds) }
    if ($SpinnerOnlyBetweenPolls) { $watchArgs += "-SpinnerOnlyBetweenPolls" }
    if ($MaxFrames -gt 0) { $watchArgs += @("-MaxFrames", [string]$MaxFrames) }
    if ($Json) { $watchArgs += "-Json" }
    if ($OutputFile) { $watchArgs += @("-OutputFile", $OutputFile) }
    if ($Json) { $result = Invoke-JsonScript $watchArgs } else { Invoke-TextScript $watchArgs; return }
  }
  "start-one" {
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "1", "-MaxTasks", "1", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $child = Invoke-JsonScript $args -IncludeParseMetadata
    $result = $child.value
    $result | Add-Member -NotePropertyName child_non_json_prefix_present -NotePropertyValue ([bool]$child.non_json_prefix_present) -Force
    $result | Add-Member -NotePropertyName child_parse_mode -NotePropertyValue ([string]$child.parse_mode) -Force
    if ($child.non_json_prefix_present) { $result | Add-Member -NotePropertyName child_non_json_prefix -NotePropertyValue ([string]$child.non_json_prefix) -Force }
    if (-not $result.PSObject.Properties["task_created"]) {
      $taskId = $null
      if ($result.final_status -and $result.final_status.campaign -and $result.final_status.campaign.steps) {
        $current = @($result.final_status.campaign.steps | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
        if ($current -and @($current.linked_task_ids).Count -gt 0) { $taskId = [string]@($current.linked_task_ids)[0] }
      }
      $result | Add-Member -NotePropertyName task_created -NotePropertyValue (-not [string]::IsNullOrWhiteSpace($taskId)) -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $taskId -Force
      $result | Add-Member -NotePropertyName task_created_summary -NotePropertyValue $(if ($taskId) { "task created: $taskId" } else { "no task created" }) -Force
    }
    if ([string]$result.runner_status -eq "held" -and [string]$result.stop_reason -eq "max_steps_reached") {
      $result.ok = $true
      $result | Add-Member -NotePropertyName bounded_completion -NotePropertyValue $true -Force
    }
  }
  "start-all" {
    $args = @("-File", ".\scripts\powershell\start-dev-queue-189-200.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-GoalPackDir", $GoalPackDir, "-CampaignId", $CampaignId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-Json") + $tokenArgs
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    if ($OutputFile) { $args += @("-OutputFile", $OutputFile) }
    $child = Invoke-JsonScript $args -IncludeParseMetadata
    $result = $child.value
    $result | Add-Member -NotePropertyName child_non_json_prefix_present -NotePropertyValue ([bool]$child.non_json_prefix_present) -Force
    $result | Add-Member -NotePropertyName child_parse_mode -NotePropertyValue ([string]$child.parse_mode) -Force
    if ($child.non_json_prefix_present) { $result | Add-Member -NotePropertyName child_non_json_prefix -NotePropertyValue ([string]$child.non_json_prefix) -Force }
    if (-not $result.PSObject.Properties["task_created"]) {
      $result | Add-Member -NotePropertyName task_created -NotePropertyValue $false -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $null -Force
      $result | Add-Member -NotePropertyName task_created_summary -NotePropertyValue "no task id surfaced by child command" -Force
    }
    if ([string]$result.runner_status -eq "held" -and [string]$result.stop_reason -eq "max_steps_reached") {
      $result.ok = $true
      $result | Add-Member -NotePropertyName bounded_completion -NotePropertyValue $true -Force
    }
  }
  "safe-pause" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "safe-pause requires -Reason." }
    if (-not $Apply) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; token_printed = $false; would_pause_project = $true; would_hold_runner = $true; would_set_stop_requested = $false; mutates = $false; reason = $Reason; summary = "safe-pause dry-run: no mutation; would pause project and hold runner with stop_requested=false." }
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $hold = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-hold", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Apply", "-Json"))
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; runner = $hold; stop_requested = [bool]$control.control.stop_requested; reason = $Reason; summary = "safe-pause applied: project paused and stop_requested=false." }
    }
  }
  "emergency-stop" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "emergency-stop requires -Reason." }
    if (-not $Apply) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; token_printed = $false; would_stop_project = $true; would_set_stop_requested = $true; mutates = $false; reason = $Reason; instructions = "Dry-run only. With -Apply, press Ctrl+C in the runner window if it is still running."; summary = "emergency-stop dry-run: no mutation; would set stop_requested=true and require operator Ctrl+C for any live runner." }
    } else {
      $control = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "stop", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; token_printed = $false; control = $control; stop_requested = [bool]$control.control.stop_requested; task_created = $false; reason = $Reason; instructions = "Press Ctrl+C in the runner window if it is still running."; summary = "emergency-stop applied: stop_requested=true; no task was created." }
    }
  }
  "resume" {
    $preflight = Invoke-Preflight
    if (-not $Apply) {
      $stopRequested = $false
      try {
        $controlState = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "status", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
        $stopRequested = [bool]$controlState.control.stop_requested
      } catch {
        $controlState = $null
      }
      $goal190Unexecuted = $false
      if ($preflight.current_step_detail) { $goal190Unexecuted = [bool]$preflight.current_step_detail.unexecuted }
      $result = [pscustomobject]@{
        ok = $true
        command = $Command
        mode = "dry-run"
        token_printed = $false
        mutates = $false
        would_clear_stop_requested = $true
        stop_requested_current = $stopRequested
        required_recovery_action = if ($stopRequested) { "Run safe-pause -Apply first to restore paused stop_requested=false, then rerun resume dry-run." } else { $null }
        would_refresh_worker_heartbeat = (Test-Path -LiteralPath $WorkerProfile -PathType Leaf)
        would_resume_runner = $true
        would_execute_goal_190 = $false
        current_step = [string]$preflight.current_step
        goal_190_unexecuted = $goal190Unexecuted
        preflight = $preflight
        next_safe_action = "Do not execute Goal 190 from Goal 188G. Run the Pre-190 Acceptance Gate, then use start-one only after explicit operator approval."
        summary = "resume dry-run: no mutation; current step is $($preflight.current_step); Goal 190 execution is blocked in this goal."
      }
    } else {
      Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json")) | Out-Null
      if (Test-Path -LiteralPath $WorkerProfile -PathType Leaf) {
        Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "register-heartbeat", "-ConfigFile", $WorkerProfile, "-Json") | Out-Null
      }
      $result = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "resume", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-WorkerProfile", $WorkerProfile, "-HermesEnvFile", $HermesEnvFile, "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes, "-MaxSteps", "12", "-MaxTasks", "12", "-StopOnFailure", "-AllowAutoMerge", "-AllowEvidenceRepair", "-HumanApproved", "-HumanApprovalReason", "Operator resumed bounded dev queue execution.", "-Apply", "-Json") + $tokenArgs)
    }
  }
  "report" {
    $report = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-report", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    $hygiene = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Hygiene", "-ColorMode", "Never", "-Json"))
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; token_printed = $false; report = $report.report; hygiene_summary = $hygiene.hygiene_summary; active_tasks = $hygiene.task_summary.active; stale_leases = $hygiene.task_summary.stale_leases }
  }
  "unlock-stale-runner" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "unlock-stale-runner requires -Reason." }
    $status = Invoke-JsonScript (@("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Json"))
    if ([string]$status.runner_lock_status -eq "active") { throw "Refusing to unlock active non-stale runner lock." }
    if ([string]$status.runner_lock_status -notin @("stale", "released", "none")) { throw "Unsupported runner lock status: $($status.runner_lock_status)" }
    if ([string]$status.runner_lock_status -in @("released", "none")) {
      $result = [pscustomobject]@{
        ok = $true
        command = $Command
        mode = if ($Apply) { "apply" } else { "dry-run" }
        token_printed = $false
        runner_lock_status = [string]$status.runner_lock_status
        lock = $status.runner_lock
        would_unlock = $false
        unlocked = $false
        requires_apply = (-not $Apply)
        reason = $Reason
        summary = "No stale runner lock is present; unlock is a no-op."
      }
      break
    }
    $unlockArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-unlock", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId) + $tokenArgs + @("-Reason", $Reason, "-Json")
    if ($Apply) { $unlockArgs += "-Apply" } else { $unlockArgs += "-DryRun" }
    $result = Invoke-JsonScript $unlockArgs
    $result | Add-Member -NotePropertyName command -NotePropertyValue $Command -Force
    $result | Add-Member -NotePropertyName mode -NotePropertyValue $(if ($Apply) { "apply" } else { "dry-run" }) -Force
    $result | Add-Member -NotePropertyName requires_apply -NotePropertyValue (-not $Apply) -Force
    $result | Add-Member -NotePropertyName reason -NotePropertyValue $Reason -Force
  }
}

if (-not $result.PSObject.Properties["command"]) {
  $result | Add-Member -NotePropertyName command -NotePropertyValue $Command
}
if (-not $result.PSObject.Properties["mode"]) {
  $result | Add-Member -NotePropertyName mode -NotePropertyValue $mode
}
if (-not $result.PSObject.Properties["token_printed"]) {
  $result | Add-Member -NotePropertyName token_printed -NotePropertyValue $false
}
Write-ControlOutput $result
