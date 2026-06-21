[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$OutputFile,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureHygieneFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 240)
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
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  if ($exitCode -ne 0) {
    throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)"
  }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Command returned empty JSON." }
  $text | ConvertFrom-Json
}

function New-EvidenceRepairPreview {
  param($Task)
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id")
    classification = "evidence-repair-only"
    preview_only = $true
    future_apply_may = @("write evidence metadata only for the existing task and related PR")
    must_not = @("create a new PR", "requeue the task", "rerun Codex", "claim the task", "modify task status")
    reason = "Existing task appears to have related PR context but recovered evidence is missing."
    recommended_record = "A future apply goal may record bounded evidence metadata for the existing task without scheduling or execution."
  }
}

function New-BlockedPreview {
  param($Task)
  $classification = [string](Get-Prop -Object $Task -Name "classification" -Default "historical-residue")
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id")
    classification = "archive-or-keep-blocked-candidate"
    source_classification = $classification
    preview_only = $true
    decision_needed = "keep-blocked vs archive"
    not_execution_candidate = $true
    reason = "The task is already blocked or historical residue and must not be scheduled by worker automation."
    future_apply_would_record = @("operator decision", "reason code", "timestamp", "no requeue", "no task execution")
    must_not = @("archive during preview", "claim", "requeue", "run Codex", "write evidence")
  }
}

function New-RequeueExclusion {
  param($Task)
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id")
    classification = "excluded_from_requeue"
    preview_only = $true
    excluded_from_worker_scheduling = $true
    reason = "Goal 315 classified this task as unsafe to requeue; it requires a separate explicit recovery policy before any retry."
    must_not = @("claim", "requeue", "execute", "schedule", "archive during preview")
  }
}

if ($FixtureHygieneFile) {
  $hygiene = Read-JsonFile -Path $FixtureHygieneFile
} else {
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-task-hygiene-report.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  $hygiene = Invoke-ChildJson -Arguments $args
}

$evidenceCandidates = @((Get-Prop -Object $hygiene -Name "evidence_repair_candidates" -Default @()) | Where-Object { $null -ne $_ })
$blockedCandidates = @((Get-Prop -Object $hygiene -Name "archive_or_keep_blocked_candidates" -Default @()) | Where-Object { $null -ne $_ })
$unsafeCandidates = @((Get-Prop -Object $hygiene -Name "unsafe_to_requeue_candidates" -Default @()) | Where-Object { $null -ne $_ })

$unsafeMap = [ordered]@{}
foreach ($task in $unsafeCandidates) {
  $taskId = [string](Get-Prop -Object $task -Name "task_id")
  if (-not [string]::IsNullOrWhiteSpace($taskId) -and -not $unsafeMap.Contains($taskId)) {
    $unsafeMap[$taskId] = New-RequeueExclusion -Task $task
  }
}

$previewOnly = $true
$report = [pscustomobject]@{
  schema = "skybridge.task_hygiene_repair_preview.v1"
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  preview_only = $previewOnly
  evidence_repair_preview = @($evidenceCandidates | ForEach-Object { New-EvidenceRepairPreview -Task $_ })
  archive_or_keep_blocked_preview = @($blockedCandidates | ForEach-Object { New-BlockedPreview -Task $_ })
  unsafe_to_requeue_exclusions = @($unsafeMap.Values)
  no_action_required = ($evidenceCandidates.Count -eq 0 -and $blockedCandidates.Count -eq 0 -and $unsafeMap.Count -eq 0)
  recommended_next_safe_action = if ($evidenceCandidates.Count -gt 0 -or $blockedCandidates.Count -gt 0) {
    "Prepare Goal 317 as an explicit apply goal for evidence metadata repair and blocked-task archive/keep decisions; keep all execution and requeue paths disabled."
  } else {
    "No Goal 315 hygiene repair preview action is currently required."
  }
  safety = [pscustomobject]@{
    preview_only = $true
    read_only = $true
    tasks_mutated = $false
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    tasks_archived = $false
    evidence_written = $false
    project_control_unpaused = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    codex_run_called = $false
    start_one_called = $false
    run_until_hold_called = $false
    logs_included = $false
    prompts_included = $false
    hermes_responses_included = $false
    token_printed = $false
  }
  tasks_mutated = $false
  tasks_claimed = $false
  tasks_requeued = $false
  tasks_cancelled = $false
  tasks_archived = $false
  evidence_written = $false
  codex_run_called = $false
  queue_apply_called = $false
  campaign_metadata_advanced = $false
  project_control_unpaused = $false
  start_one_called = $false
  run_until_hold_called = $false
  token_printed = $false
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "Project:      $($report.project_id)"
  "PreviewOnly:  true"
  "Evidence:     $(@($report.evidence_repair_preview).Count)"
  "Blocked:      $(@($report.archive_or_keep_blocked_preview).Count)"
  "Excluded:     $(@($report.unsafe_to_requeue_exclusions).Count)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
