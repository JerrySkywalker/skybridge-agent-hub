[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "start-one-apply-pilot-docs-001",
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTaskFile,
  [string]$FixtureStartOneApplyPilotFile,
  [string]$FixtureEvidenceFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-BoolProp {
  param($Object, [string]$Name, [bool]$Default = $false)
  $value = Get-Prop -Object $Object -Name $Name -Default $Default
  if ($null -eq $value) { return $Default }
  return [bool]$value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 260)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Invoke-ChildJson {
  param([Parameter(Mandatory = $true)][string[]]$Arguments, [switch]$AllowNonZero)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -eq 0 -and $null -ne $parsed) { return $parsed }
  if ($AllowNonZero -and $null -ne $parsed) { return $parsed }
  throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)"
}

function Get-Task {
  if ($FixtureTaskFile) {
    $fixture = Read-JsonFile -Path $FixtureTaskFile
    return (Get-Prop -Object $fixture -Name "task" -Default $fixture)
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return $null }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return (Get-Prop -Object $response -Name "task" -Default $response)
  } catch {
    return $null
  }
}

function Get-ApplyPreview {
  if ($FixtureStartOneApplyPilotFile) { return Read-JsonFile -Path $FixtureStartOneApplyPilotFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-start-one-apply-pilot.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Preview",
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  try { return Invoke-ChildJson -Arguments $args -AllowNonZero } catch { return $null }
}

function Get-LocalEvidence {
  if ($FixtureEvidenceFile) { return Read-JsonFile -Path $FixtureEvidenceFile }
  $path = Join-Path $RepoRoot ".agent\tmp\start-one-apply-pilot\start-one-apply-pilot-evidence.json"
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    try {
      $evidence = Read-JsonFile -Path $path
      if ([string](Get-Prop -Object $evidence -Name "task_id" -Default "") -eq $TaskId) { return $evidence }
    } catch {}
  }
  return $null
}

function Get-TerminalState {
  param($Task, $Apply, $Evidence)
  $fromApply = [string](Get-Prop -Object $Apply -Name "terminal_state" -Default "")
  if ($fromApply) { return $fromApply }
  $fromEvidence = [string](Get-Prop -Object $Evidence -Name "terminal_state" -Default "")
  if ($fromEvidence) { return $fromEvidence }
  $status = ([string](Get-Prop -Object $Task -Name "status" -Default "not_reported")).ToLowerInvariant()
  if ($status -eq "completed") { return "completed_with_evidence" }
  if ($status -in @("failed", "failed_with_evidence")) { return "failed_with_evidence" }
  if ($status -in @("running", "claimed")) { return "held_after_anomaly" }
  if ($status -eq "queued") { return "queued_not_terminal" }
  return "not_reported"
}

$task = Get-Task
$apply = Get-ApplyPreview
$evidence = Get-LocalEvidence
$terminalState = Get-TerminalState -Task $task -Apply $apply -Evidence $evidence
$failureCategory = [string](Get-Prop -Object $apply -Name "failure_category" -Default (Get-Prop -Object $evidence -Name "failure_category" -Default ""))
$holdReason = [string](Get-Prop -Object $apply -Name "hold_reason" -Default "")
if (-not $holdReason -and $terminalState -notin @("completed_with_evidence", "already_completed_noop", "queued_not_terminal")) {
  $holdReason = if ($failureCategory) { $failureCategory } else { $terminalState }
}
$evidenceSummaryFromApply = Get-Prop -Object $apply -Name "evidence_summary"
$evidencePresent = (($null -ne $evidence) -or (Get-BoolProp -Object $evidenceSummaryFromApply -Name "evidence_present" -Default $false))
$filesChanged = @()
if ($evidence) { $filesChanged = @((Get-Prop -Object $evidence -Name "files_changed" -Default @()) | ForEach-Object { [string]$_ }) }
elseif ($evidenceSummaryFromApply) { $filesChanged = @((Get-Prop -Object $evidenceSummaryFromApply -Name "files_changed" -Default @()) | ForEach-Object { [string]$_ }) }

$projectControlUnpaused = (Get-BoolProp -Object (Get-Prop -Object $apply -Name "project_control") -Name "project_control_unpaused") -or (Get-BoolProp -Object (Get-Prop -Object $evidence -Name "safety") -Name "project_control_unpaused")
$runUntilHoldCalled = (Get-BoolProp -Object (Get-Prop -Object $apply -Name "forbidden_actions") -Name "run_until_hold_called") -or (Get-BoolProp -Object (Get-Prop -Object $evidence -Name "safety") -Name "run_until_hold_called")
$oldResidueSelected = (Get-BoolProp -Object (Get-Prop -Object $evidence -Name "safety") -Name "old_residue_selected") -or (-not (Get-BoolProp -Object (Get-Prop -Object $apply -Name "old_residue_exclusion") -Name "no_old_residue_eligible" -Default $true))
$manualReview = Get-BoolProp -Object $apply -Name "manual_operator_review_needed" -Default ($terminalState -in @("failed_with_evidence", "failed_needs_operator_review", "held_after_anomaly", "claim_expired", "evidence_missing", "evidence_write_failed", "validation_failed", "unsafe_path_changed"))

$recommended = if ($projectControlUnpaused -or $runUntilHoldCalled -or $oldResidueSelected) {
  "FAILED_CLOSED: stop and review unsafe mutation flags."
} elseif ($terminalState -in @("completed_with_evidence", "already_completed_noop")) {
  "No action required for the completed deterministic pilot; keep project_control paused."
} elseif ($terminalState -eq "queued_not_terminal") {
  "Preview only; do not run until an explicit single-task apply goal authorizes it."
} else {
  "Hold for operator review; do not retry, requeue, or run run-until-hold."
}

$report = [pscustomobject]@{
  schema = "skybridge.start_one_hold_report.v1"
  ok = (-not $projectControlUnpaused -and -not $runUntilHoldCalled -and -not $oldResidueSelected)
  task_id = $TaskId
  current_status = [string](Get-Prop -Object $task -Name "status" -Default (Get-Prop -Object (Get-Prop -Object $apply -Name "pilot_task_lookup") -Name "status" -Default "not_reported"))
  terminal_state = $terminalState
  hold_reason = if ($holdReason) { $holdReason } else { $null }
  evidence_present = $evidencePresent
  evidence_summary = [pscustomobject]@{
    schema = [string](Get-Prop -Object $evidence -Name "schema" -Default (Get-Prop -Object $evidenceSummaryFromApply -Name "schema" -Default "not_reported"))
    files_changed = @($filesChanged)
    allowed_paths = @((Get-Prop -Object $evidence -Name "allowed_paths" -Default @("docs/operations/START_ONE_APPLY_PILOT.md")) | ForEach-Object { [string]$_ })
    failure_category = if ($failureCategory) { $failureCategory } else { $null }
    prompt_content_included = $false
    log_content_included = $false
    credential_values_included = $false
    token_printed = $false
  }
  old_residue_selected = $oldResidueSelected
  project_control_unpaused = $projectControlUnpaused
  run_until_hold_called = $runUntilHoldCalled
  manual_operator_review_needed = $manualReview
  recommended_next_safe_action = $recommended
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} else {
  "Schema:       $($report.schema)"
  "OK:           $($report.ok)"
  "Task:         $($report.task_id)"
  "Status:       $($report.current_status)"
  "Terminal:     $($report.terminal_state)"
  "HoldReason:   $(if ($report.hold_reason) { $report.hold_reason } else { 'none' })"
  "Evidence:     $($report.evidence_present)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
