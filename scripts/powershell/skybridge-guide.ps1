[CmdletBinding()]
param(
  [ValidateSet("status", "status-active", "status-recent", "status-worker", "status-task", "status-failed", "status-recovered", "status-proposals", "submit-preview", "submit-apply", "run-once-preview", "run-once-apply", "inspect-task", "inspect-worker", "pause", "start", "plan-preview", "plan-apply", "proposals", "proposal-list", "proposal-show", "proposal-approve", "proposal-accept", "proposal-reject", "proposal-defer", "proposal-convert", "proposal-convert-preview", "proposal-approved", "proposal-pending-review", "supervise-preview", "supervise-apply", "supervise-status", "hermes-health", "hermes-preview", "hermes-preview-summary")]
  [string]$Mode = "status",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$WorkerProfile,
  [string]$WorkerId,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$GoalId,
  [string]$GoalTitle,
  [string]$TaskId,
  [string]$TaskTitle,
  [string]$TaskBody,
  [string]$TaskBodyFile,
  [string]$MasterGoalId,
  [string]$ProposalId,
  [string]$Reason,
  [string]$SupersededBy,
  [string]$Description,
  [string[]]$Constraints = @(),
  [string]$ConstraintsFile,
  [string]$ConstraintsJson,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [int]$MaxRounds = 1,
  [switch]$AllowHighRisk,
  [switch]$NoRun,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp"
)

$ErrorActionPreference = "Stop"

function Add-CommonAuthArgs {
  param([string[]]$Arguments)
  $result = @($Arguments)
  if ($TokenEnvVar) { $result += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $result += @("-TokenFile", $TokenFile) }
  return $result
}

function Invoke-GuideJsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function New-GuideNextCommand {
  param([string]$NextMode)
  $parts = @(
    "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1",
    "-Mode $NextMode",
    "-ApiBase `"$ApiBase`"",
    "-ProjectId `"$ProjectId`""
  )
  if ($GoalId) { $parts += "-GoalId `"$GoalId`"" }
  if ($GoalTitle -and ($NextMode -like "run-once*" -or $NextMode -like "plan-*" -or $NextMode -like "supervise*")) { $parts += "-GoalTitle `"$GoalTitle`"" }
  if ($TaskId) { $parts += "-TaskId `"$TaskId`"" }
  if ($WorkerId) { $parts += "-WorkerId `"$WorkerId`"" }
  if ($TaskTitle -and ($NextMode -like "run-once*" -or $NextMode -like "plan-*" -or $NextMode -like "supervise*")) { $parts += "-TaskTitle `"$TaskTitle`"" }
  if ($TaskBody -and $NextMode -like "run-once*") { $parts += "-TaskBody `"$TaskBody`"" }
  if ($TaskBodyFile -and $NextMode -like "run-once*") { $parts += "-TaskBodyFile `"$TaskBodyFile`"" }
  if ($MasterGoalId) { $parts += "-MasterGoalId `"$MasterGoalId`"" }
  if ($Reason -and ($NextMode -like "proposal-*")) { $parts += "-Reason `"$Reason`"" }
  if ($SupersededBy -and ($NextMode -like "proposal-*")) { $parts += "-SupersededBy `"$SupersededBy`"" }
  if ($ConstraintsFile -and $NextMode -like "hermes-preview*") { $parts += "-ConstraintsFile `"$ConstraintsFile`"" }
  if ($HermesEnvFile -and $NextMode -like "hermes-*") { $parts += "-HermesEnvFile `"$HermesEnvFile`"" }
  if ($HermesApiBase -and $NextMode -like "hermes-*") { $parts += "-HermesApiBase `"$HermesApiBase`"" }
  if ($ProposalId) { $parts += "-ProposalId `"$ProposalId`"" }
  if ($NextMode -like "supervise*") { $parts += "-MaxRounds $MaxRounds" }
  if ($WorkerProfile) { $parts += "-WorkerProfile `"$WorkerProfile`"" }
  elseif ($NextMode -like "run-once*" -or $NextMode -like "supervise*") { $parts += "-WorkerProfile `"`$HOME\.skybridge\worker.<hostname>.json`"" }
  if ($TokenFile) { $parts += "-TokenFile `"$TokenFile`"" }
  elseif ($TokenEnvVar) { $parts += "-TokenEnvVar `"$TokenEnvVar`"" }
  else { $parts += "# add -TokenFile or -TokenEnvVar for remote auth" }
  return ($parts -join " ")
}

function New-GuideMasterGoalId {
  param([string]$Title)
  $slug = (($Title ?? "").ToLowerInvariant() -replace "[^a-z0-9]+", "-" -replace "^-|-$", "")
  if ([string]::IsNullOrWhiteSpace($slug)) { return $null }
  return "master-goal-$($slug.Substring(0, [Math]::Min(72, $slug.Length)))"
}

function Write-GuideResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 50 -Compress
    return
  }
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.goal_id) { "Goal:         $($Result.goal_id)" }
  if ($Result.task_id) { "Task:         $($Result.task_id)" }
  "Action:       $($Result.action)"
  "TokenPrinted: false"
  if ($Result.next_command) { "Next:         $($Result.next_command)" }
  if ($Result.next_note) { "Note:         $($Result.next_note)" }
  if ($Result.task_detail) {
    "RawStatus:    $($Result.task_detail.raw_status)"
    "Display:      $($Result.task_detail.display_status)"
    "Recovered:    $($Result.task_detail.recovered)"
    "CI:           $(if ($Result.task_detail.ci_status) { $Result.task_detail.ci_status } else { '-' })"
    "PR:           $(if ($Result.task_detail.pr_url) { $Result.task_detail.pr_url } else { '-' })"
    "Summary:      $(if ($Result.task_detail.summary) { $Result.task_detail.summary } else { '-' })"
  }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$result = $null

switch ($Mode) {
  "status" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status"; api_base = $ApiBase; project_id = $ProjectId; task_id = $TaskId; goal_id = $GoalId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "submit-preview"; status = $payload }
  }
  "status-active" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-active.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ActiveOnly", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-active"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-recent"; status = $payload }
  }
  "status-recent" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-recent.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-RecentTasks", "10", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-recent"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-active"; status = $payload }
  }
  "status-worker" {
    if ([string]::IsNullOrWhiteSpace($WorkerId)) { throw "status-worker requires -WorkerId." }
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-worker.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-WorkerId", $WorkerId, "-TaskLimit", "20", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-worker"; api_base = $ApiBase; project_id = $ProjectId; worker_id = $WorkerId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-recent"; status = $payload }
  }
  "status-task" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "status-task requires -TaskId." }
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-task.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TaskId", $TaskId, "-EventLimit", "10", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $taskDetail = @($payload.tasks)[0]
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-task"; api_base = $ApiBase; project_id = $ProjectId; task_id = $TaskId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-recent"; task_detail = $taskDetail; status = $payload }
  }
  "status-failed" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-failed.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TaskStatus", "failed", "-ExcludeRecovered", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-failed"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-recovered"; status = $payload }
  }
  "status-recovered" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-recovered.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-RecoveredOnly", "-TaskLimit", "20", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-recovered"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "status-failed"; status = $payload }
  }
  "status-proposals" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-status-proposals.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ShowProposals", "-ProposalLimit", "10", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "status-proposals"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "proposal-list"; status = $payload }
  }
  "submit-preview" {
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { throw "submit-preview requires -TaskTitle." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-EnsureProject", "-EnsureGoal", "-DryRun", "-Json")
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    $args += @("-TaskTitle", $TaskTitle)
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "dry-run-submit"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $payload.goal.id; task_id = $payload.task.id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "submit-apply"; submit = $payload }
  }
  "submit-apply" {
    if ($DryRun) { throw "submit-apply does not accept -DryRun. Use submit-preview for dry-run behavior." }
    if (-not $Apply) { throw "submit-apply requires explicit -Apply." }
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { throw "submit-apply requires -TaskTitle." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-submit.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-EnsureProject", "-EnsureGoal", "-Apply", "-Json")
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    $args += @("-TaskTitle", $TaskTitle)
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "applied-submit"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $payload.goal.id; task_id = $payload.task.id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; submit = $payload }
  }
  "run-once-preview" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-DryRun", "-Json", "-OutputDir", $OutputDir)
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) { $args += "-NoSubmit" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $nextNote = $null
    if ([string]::IsNullOrWhiteSpace($TaskTitle)) {
      $nextNote = "Run submit-apply first, then run-once-apply against the accepted queued task with -NoSubmit semantics."
    }
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "dry-run-once"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $payload.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-apply"; next_note = $nextNote; run_once = $payload }
  }
  "run-once-apply" {
    if ($DryRun) { throw "run-once-apply does not accept -DryRun. Use run-once-preview for dry-run behavior." }
    if (-not $Apply) { throw "run-once-apply requires explicit -Apply." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Apply", "-Json", "-OutputDir", $OutputDir)
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($GoalId) { $args += @("-GoalId", $GoalId) }
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($TaskTitle) { $args += @("-TaskTitle", $TaskTitle) } else { $args += "-NoSubmit" }
    if ($GoalTitle) { $args += @("-GoalTitle", $GoalTitle) }
    if ($TaskBody) { $args += @("-TaskBody", $TaskBody) }
    if ($TaskBodyFile) { $args += @("-TaskBodyFile", $TaskBodyFile) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "applied-run-once"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $payload.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "inspect-task"; run_once = $payload }
  }
  "inspect-task" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "inspect-task requires -TaskId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TaskId", $TaskId, "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $taskDetail = @($payload.tasks)[0]
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "inspect-task"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; task_detail = $taskDetail; status = $payload }
  }
  "inspect-worker" {
    if ([string]::IsNullOrWhiteSpace($WorkerProfile)) { throw "inspect-worker requires -WorkerProfile." }
    $payload = Invoke-GuideJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-worker-status.ps1", "-Command", "status", "-ConfigFile", $WorkerProfile, "-ProjectId", $ProjectId, "-Json")
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "inspect-worker"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; worker = $payload }
  }
  "pause" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "pause", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "pause"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "status"; control = $payload }
  }
  "start" {
    if ($DryRun) { throw "start does not accept -DryRun. Omit -Apply to preview start intent through status/plan modes." }
    if (-not $Apply) { throw "start requires explicit -Apply." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-control.ps1", "-Command", "start", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MaxTasks", "1", "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "start"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; control = $payload }
  }
  "plan-preview" {
    if ([string]::IsNullOrWhiteSpace($TaskTitle) -and [string]::IsNullOrWhiteSpace($GoalTitle)) { throw "plan-preview requires -GoalTitle or -TaskTitle as the master goal title." }
    $planTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-plan.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Title", $planTitle, "-DryRun", "-Json", "-OutputFile", (Join-Path $OutputDir "skybridge-guide-plan-preview.json"))
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    if ($Description) { $args += @("-Description", $Description) }
    foreach ($constraint in @($Constraints)) { $args += @("-Constraints", $constraint) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $MasterGoalId = $payload.master_goal.master_goal_id
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "plan-preview"; api_base = $ApiBase; project_id = $ProjectId; goal_id = $GoalId; task_id = $TaskId; master_goal_id = $payload.master_goal.master_goal_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "plan-apply"; plan = $payload }
  }
  "plan-apply" {
    if ($DryRun) { throw "plan-apply does not accept -DryRun. Use plan-preview for dry-run behavior." }
    if (-not $Apply) { throw "plan-apply requires explicit -Apply." }
    if ([string]::IsNullOrWhiteSpace($TaskTitle) -and [string]::IsNullOrWhiteSpace($GoalTitle)) { throw "plan-apply requires -GoalTitle or -TaskTitle as the master goal title." }
    $planTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-plan.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Title", $planTitle, "-Apply", "-Json", "-OutputFile", (Join-Path $OutputDir "skybridge-guide-plan-apply.json"))
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    if ($Description) { $args += @("-Description", $Description) }
    foreach ($constraint in @($Constraints)) { $args += @("-Constraints", $constraint) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $MasterGoalId = $payload.master_goal.master_goal_id
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "plan-apply"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $payload.master_goal.master_goal_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposals"; plan = $payload }
  }
  "proposals" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "list", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposals"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-show"; proposals = $payload }
  }
  "proposal-list" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "list", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Json")
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-list"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-show"; proposals = $payload }
  }
  "proposal-show" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-show requires -ProposalId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "show", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Json")
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-show"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-approve"; proposal = $payload.proposal }
  }
  "proposal-approve" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-approve requires -ProposalId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "approve", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Json")
    if ($Reason) { $args += @("-Reason", $Reason) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-approve"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-convert"; proposal = $payload.proposal; validation = $payload.validation }
  }
  "proposal-accept" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-accept requires -ProposalId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "approve", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Json")
    if ($Reason) { $args += @("-Reason", $Reason) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-approve"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-convert"; proposal = $payload.proposal; validation = $payload.validation }
  }
  "proposal-reject" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-reject requires -ProposalId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "proposal-reject requires -Reason." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "reject", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Reason", $Reason, "-Json")
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-reject"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-list"; proposal = $payload.proposal }
  }
  "proposal-defer" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-defer requires -ProposalId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "proposal-defer requires -Reason." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "defer", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Reason", $Reason, "-Json")
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-defer"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-list"; proposal = $payload.proposal }
  }
  "proposal-approved" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "list", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Status", "approved", "-Json")
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-approved"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-convert"; proposals = $payload }
  }
  "proposal-pending-review" {
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "list", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ReviewStatus", "proposed", "-Json")
    if ($MasterGoalId) { $args += @("-MasterGoalId", $MasterGoalId) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-pending-review"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "proposal-show"; proposals = $payload }
  }
  "proposal-convert" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-convert requires -ProposalId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "convert", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-Json")
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    if ($Apply) { $args += "-Apply" } else { $args += "-DryRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-convert"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; task_id = $payload.task.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; proposal = $payload.proposal; task = $payload.task }
  }
  "proposal-convert-preview" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal-convert-preview requires -ProposalId." }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-proposal.ps1", "-Command", "convert", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ProposalId", $ProposalId, "-DryRun", "-Json")
    if ($TaskId) { $args += @("-TaskId", $TaskId) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "proposal-convert-preview"; api_base = $ApiBase; project_id = $ProjectId; proposal_id = $ProposalId; task_id = $payload.task.task_id; token_printed = $false; next_command = New-GuideNextCommand -NextMode "run-once-preview"; proposal = $payload.proposal; task = $payload.task }
  }
  "supervise-preview" {
    if ([string]::IsNullOrWhiteSpace($GoalTitle) -and [string]::IsNullOrWhiteSpace($TaskTitle)) { throw "supervise-preview requires -GoalTitle or -TaskTitle as the master goal title." }
    $superviseTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-GuideMasterGoalId -Title $superviseTitle }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-supervise.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-GoalTitle", $superviseTitle, "-MaxRounds", [string]$MaxRounds, "-DryRun", "-Json", "-OutputDir", $OutputDir)
    if ($Description) { $args += @("-Description", $Description) }
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($AllowHighRisk) { $args += "-AllowHighRisk" }
    if ($NoRun) { $args += "-NoRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "supervise-preview"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "supervise-apply"; supervise = $payload }
  }
  "supervise-apply" {
    if ($DryRun) { throw "supervise-apply does not accept -DryRun. Use supervise-preview for dry-run behavior." }
    if (-not $Apply) { throw "supervise-apply requires explicit -Apply." }
    if ([string]::IsNullOrWhiteSpace($GoalTitle) -and [string]::IsNullOrWhiteSpace($TaskTitle)) { throw "supervise-apply requires -GoalTitle or -TaskTitle as the master goal title." }
    $superviseTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-GuideMasterGoalId -Title $superviseTitle }
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-supervise.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-GoalTitle", $superviseTitle, "-MaxRounds", [string]$MaxRounds, "-Apply", "-Json", "-OutputDir", $OutputDir)
    if ($Description) { $args += @("-Description", $Description) }
    if ($WorkerProfile) { $args += @("-WorkerProfile", $WorkerProfile) }
    if ($AllowHighRisk) { $args += "-AllowHighRisk" }
    if ($NoRun) { $args += "-NoRun" }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "supervise-apply"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "inspect-task"; supervise = $payload }
  }
  "supervise-status" {
    $snapshot = Join-Path $OutputDir "skybridge-guide-supervise-status.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-ShowAll", "-Json", "-OutputFile", $snapshot)
    $payload = Invoke-GuideJsonScript -Arguments $args
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "supervise-status"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; output_file = $snapshot; next_command = New-GuideNextCommand -NextMode "supervise-preview"; status = $payload }
  }
  "hermes-health" {
    $args = @("-File", ".\scripts\powershell\skybridge-hermes-health.ps1", "-Json")
    if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
    if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $nextNote = if ($payload.direct_https -eq $true) { "Direct HTTPS Hermes API is configured for this check." } else { "Hermes API is not using direct HTTPS; tunnel fallback may still be required." }
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "hermes-health"; api_base = $ApiBase; project_id = $ProjectId; token_printed = $false; next_command = New-GuideNextCommand -NextMode "hermes-preview"; next_note = $nextNote; hermes = $payload }
  }
  "hermes-preview" {
    if ([string]::IsNullOrWhiteSpace($GoalTitle) -and [string]::IsNullOrWhiteSpace($TaskTitle)) { throw "hermes-preview requires -GoalTitle or -TaskTitle as the master goal title." }
    $previewTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-GuideMasterGoalId -Title $previewTitle }
    $previewOutput = Join-Path $OutputDir "skybridge-guide-hermes-preview.json"
    $summaryOutput = Join-Path $OutputDir "hermes-preview-summary.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-hermes-preview.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-Title", $previewTitle, "-Json", "-OutputFile", $previewOutput, "-SummaryOutputFile", $summaryOutput)
    if ($Description) { $args += @("-Description", $Description) }
    if ($ConstraintsFile) { $args += @("-ConstraintsFile", $ConstraintsFile) }
    if ($ConstraintsJson) { $args += @("-ConstraintsJson", $ConstraintsJson) }
    foreach ($constraint in @($Constraints)) { $args += @("-Constraints", $constraint) }
    if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
    if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $nextNote = "Preview only: review proposals; do not convert or run workers until an apply sprint is explicitly authorized."
    if ($payload.summary.direct_https -ne $true) { $nextNote = "$nextNote Direct HTTPS is not configured for this run; tunnel fallback may still be in use." }
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "hermes-preview"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; output_file = $previewOutput; summary_output_file = $summaryOutput; next_command = New-GuideNextCommand -NextMode "hermes-preview-summary"; next_note = $nextNote; preview = $payload }
  }
  "hermes-preview-summary" {
    if ([string]::IsNullOrWhiteSpace($GoalTitle) -and [string]::IsNullOrWhiteSpace($TaskTitle)) { throw "hermes-preview-summary requires -GoalTitle or -TaskTitle as the master goal title." }
    $previewTitle = if ($GoalTitle) { $GoalTitle } else { $TaskTitle }
    if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-GuideMasterGoalId -Title $previewTitle }
    $summaryOutput = Join-Path $OutputDir "hermes-preview-summary.json"
    $args = Add-CommonAuthArgs @("-File", ".\scripts\powershell\skybridge-hermes-preview.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-MasterGoalId", $MasterGoalId, "-Title", $previewTitle, "-Json", "-SummaryOnly", "-SummaryOutputFile", $summaryOutput)
    if ($Description) { $args += @("-Description", $Description) }
    if ($ConstraintsFile) { $args += @("-ConstraintsFile", $ConstraintsFile) }
    if ($ConstraintsJson) { $args += @("-ConstraintsJson", $ConstraintsJson) }
    foreach ($constraint in @($Constraints)) { $args += @("-Constraints", $constraint) }
    if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
    if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
    $payload = Invoke-GuideJsonScript -Arguments $args
    $nextNote = "Summary only: no proposal conversion, worker PollOnce or project control mutation was run."
    $result = [pscustomobject]@{ ok = $true; mode = $Mode; action = "hermes-preview-summary"; api_base = $ApiBase; project_id = $ProjectId; master_goal_id = $MasterGoalId; token_printed = $false; summary_output_file = $summaryOutput; next_command = New-GuideNextCommand -NextMode "status"; next_note = $nextNote; summary = $payload }
  }
}

Write-GuideResult -Result $result
