[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$Apply,
  [string]$Confirm,
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$OutputJsonFile,
  [string]$OutputMarkdownFile,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureHygieneFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

$RequiredConfirm = "I_UNDERSTAND_GOAL_317_HYGIENE_METADATA_ONLY"
$ExpectedEvidenceIds = @("remote-docs-exec-pilot-001")
$ExpectedBlockedIds = @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001")
$ForbiddenTaskStatuses = @("queued", "claimed", "running")
$script:ResolvedWorkerToken = $null

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 260)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  if (-not [string]::IsNullOrWhiteSpace($script:ResolvedWorkerToken)) {
    $safe = $safe.Replace($script:ResolvedWorkerToken, "[redacted]")
  }
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Get-EnvironmentValue {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  return $value.Trim()
}

function Resolve-WorkerToken {
  $envName = if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar)) { $TokenEnvVar } else { "SKYBRIDGE_WORKER_TOKEN" }
  $token = Get-EnvironmentValue -Name $envName
  if (-not [string]::IsNullOrWhiteSpace($token)) { return $token }

  $resolvedTokenFile = $null
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) {
    $resolvedTokenFile = $TokenFile
  } else {
    $resolvedTokenFile = Get-EnvironmentValue -Name "SKYBRIDGE_WORKER_TOKEN_FILE"
  }

  if (-not [string]::IsNullOrWhiteSpace($resolvedTokenFile)) {
    if (-not (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf)) {
      throw "Worker token file was configured but was not found."
    }
    $fileToken = (Get-Content -LiteralPath $resolvedTokenFile -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($fileToken)) { return $fileToken }
  }

  return $null
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

function Invoke-SkyBridgeJson {
  param([string]$Method, [string]$Path, $Body = $null)
  $uri = "$($script:ResolvedApiBase.TrimEnd('/'))$Path"
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($script:ResolvedWorkerToken)) {
    $headers["Authorization"] = "Bearer $script:ResolvedWorkerToken"
  }
  try {
    if ($null -eq $Body) {
      if ($headers.Count -gt 0) { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds }
      return Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec $TimeoutSeconds
    }
    if ($headers.Count -gt 0) {
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
    }
    Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
  } catch {
    throw (ConvertTo-SafeText -Text $_.Exception.Message)
  }
}

function Get-RepairPreview {
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-task-hygiene-repair-preview.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($script:ResolvedApiBase) { $args += @("-ApiBase", $script:ResolvedApiBase) }
  if ($FixtureHygieneFile) { $args += @("-FixtureHygieneFile", $FixtureHygieneFile) }
  Invoke-ChildJson -Arguments $args
}

function Get-TaskSnapshot {
  param([string[]]$TaskIds)
  if (-not $script:ResolvedApiBase) {
    return [pscustomobject]@{ available = $false; tasks = @(); project_control_state = "unknown"; token_printed = $false }
  }
  $tasks = @()
  try {
    $response = Invoke-SkyBridgeJson -Method "GET" -Path ("/v1/tasks?project_id={0}" -f [Uri]::EscapeDataString($ProjectId))
    $tasks = @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $TaskIds -contains [string](Get-Prop -Object $_ -Name "task_id") } | ForEach-Object {
      [pscustomobject]@{
        task_id = [string](Get-Prop -Object $_ -Name "task_id")
        status = [string](Get-Prop -Object $_ -Name "status")
        assigned_worker_id = Get-Prop -Object $_ -Name "assigned_worker_id"
        claim_present = ($null -ne (Get-Prop -Object $_ -Name "claim"))
        lease_present = ($null -ne (Get-Prop -Object $_ -Name "lease"))
        hygiene_metadata_present = ($null -ne (Get-Prop -Object $_ -Name "hygiene_metadata"))
      }
    })
  } catch {}
  $controlState = "unknown"
  try {
    $statusArgs = @("-File", (Join-Path $PSScriptRoot "skybridge-status.ps1"), "-ApiBase", $script:ResolvedApiBase, "-ProjectId", $ProjectId, "-Json", "-TimeoutSeconds", [string]$TimeoutSeconds)
    $status = Invoke-ChildJson -Arguments $statusArgs -AllowNonZero
    $control = Get-Prop -Object $status -Name "control_summary" -Default (Get-Prop -Object $status -Name "control")
    $controlState = [string](Get-Prop -Object $control -Name "state" -Default "unknown")
  } catch {}
  [pscustomobject]@{ available = $true; tasks = @($tasks); project_control_state = $controlState; token_printed = $false }
}

function New-Action {
  param([string]$Kind, [string]$TaskId, [string]$Operation, [string]$Reason)
  [pscustomobject]@{
    kind = $Kind
    task_id = $TaskId
    operation = $Operation
    metadata_only = $true
    reason = $Reason
    forbidden_status_transitions = @("queued", "claimed", "running")
    no_claim = $true
    no_requeue = $true
    no_execution = $true
  }
}

function Assert-ExactSet {
  param([string[]]$Actual, [string[]]$Expected, [string]$Name)
  $a = @($Actual | Sort-Object)
  $e = @($Expected | Sort-Object)
  if (($a -join "`n") -ne ($e -join "`n")) {
    throw "$Name did not match the fixed Goal 317 task id set."
  }
}

$mode = if ($Apply) { "apply" } else { "preview" }
if ($Apply -and $Preview) { throw "Use only one of -Preview or -Apply." }
if ($Apply -and $Confirm -ne $RequiredConfirm) { throw "Apply requires exact confirmation string: $RequiredConfirm" }

$script:ResolvedWorkerToken = Resolve-WorkerToken
if ($Apply -and [string]::IsNullOrWhiteSpace($script:ResolvedWorkerToken)) {
  throw "Apply requires worker auth. Provide -TokenEnvVar, SKYBRIDGE_WORKER_TOKEN, -TokenFile, or SKYBRIDGE_WORKER_TOKEN_FILE."
}

$script:ResolvedApiBase = $null
if (-not $FixtureHygieneFile -or $ApiBase -or $Apply) {
  $script:ResolvedApiBase = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
  Assert-SkybridgeApiBaseUsable -ApiBase $script:ResolvedApiBase
  Assert-SkybridgeApiBaseService -ApiBase $script:ResolvedApiBase -TimeoutSeconds $TimeoutSeconds | Out-Null
}

$repairPreview = Get-RepairPreview
$evidenceIds = @((Get-Prop -Object $repairPreview -Name "evidence_repair_preview" -Default @()) | ForEach-Object { [string](Get-Prop -Object $_ -Name "task_id") })
$blockedIds = @((Get-Prop -Object $repairPreview -Name "archive_or_keep_blocked_preview" -Default @()) | ForEach-Object { [string](Get-Prop -Object $_ -Name "task_id") })
$unsafeIds = @((Get-Prop -Object $repairPreview -Name "unsafe_to_requeue_exclusions" -Default @()) | ForEach-Object { [string](Get-Prop -Object $_ -Name "task_id") })
$allPlannedIds = @($evidenceIds + $blockedIds + $unsafeIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

$planned = [pscustomobject]@{
  evidence_repair_actions = @($evidenceIds | ForEach-Object { New-Action -Kind "evidence_repair" -TaskId $_ -Operation "mark_evidence_repair_applied" -Reason "Record recovered evidence metadata only; no new PR, no requeue, no rerun." })
  archive_or_keep_blocked_actions = @($blockedIds | ForEach-Object { New-Action -Kind "keep_blocked_or_archive" -TaskId $_ -Operation "mark_keep_blocked" -Reason "Historical blocked task remains excluded from worker scheduling." })
  unsafe_to_requeue_exclusion_actions = @($unsafeIds | ForEach-Object { New-Action -Kind "excluded_from_requeue" -TaskId $_ -Operation "mark_excluded_from_requeue" -Reason "Unsafe to requeue from Goal 315/316 hygiene classification." })
  no_action_required = [bool](Get-Prop -Object $repairPreview -Name "no_action_required" -Default $false)
  forbidden_actions = [pscustomobject]@{
    task_status_to_queued = $false
    task_status_to_claimed = $false
    task_status_to_running = $false
    claim_task = $false
    requeue_task = $false
    execute_task = $false
    codex_run = $false
    project_control_unpause = $false
    start_one = $false
    run_until_hold = $false
  }
}

$before = Get-TaskSnapshot -TaskIds $allPlannedIds
$applied = @()
$warnings = [System.Collections.Generic.List[string]]::new()

if ($mode -eq "apply") {
  Assert-ExactSet -Actual $evidenceIds -Expected $ExpectedEvidenceIds -Name "evidence repair candidates"
  Assert-ExactSet -Actual $blockedIds -Expected $ExpectedBlockedIds -Name "blocked candidates"
  if ($unsafeIds.Count -ne 11) { throw "unsafe-to-requeue candidate count did not match the fixed Goal 316 preview count." }
  foreach ($task in @($before.tasks)) {
    if ($ForbiddenTaskStatuses -contains [string]$task.status) { throw "Refusing to apply metadata to active task $($task.task_id)." }
  }

  foreach ($taskId in $evidenceIds) {
    $evidenceBody = @{
      evidence_summary = @{
        task_id = $taskId
        summary = "Goal 317 metadata-only evidence repair: no new PR, no requeue, no rerun."
        validation_status = "metadata_only"
        ci_status = "not_rerun"
        risk_status = "low_metadata_only"
        recovered = $true
        recovery_status = "goal_317_metadata_repaired"
        created_at = (Get-Date).ToUniversalTime().ToString("o")
      }
      summary = "Goal 317 evidence metadata repair applied; no task execution occurred."
    }
    Invoke-SkyBridgeJson -Method "POST" -Path ("/v1/tasks/{0}/evidence-repair" -f [Uri]::EscapeDataString($taskId)) -Body $evidenceBody | Out-Null
    Invoke-SkyBridgeJson -Method "POST" -Path ("/v1/tasks/{0}/hygiene-metadata" -f [Uri]::EscapeDataString($taskId)) -Body @{
      project_id = $ProjectId
      operation = "mark_evidence_repair_applied"
      reason = "Goal 317 metadata-only evidence repair; no new PR, no requeue, no rerun."
    } | Out-Null
    $applied += New-Action -Kind "evidence_repair" -TaskId $taskId -Operation "mark_evidence_repair_applied" -Reason "Applied metadata only."
  }
  foreach ($taskId in $blockedIds) {
    Invoke-SkyBridgeJson -Method "POST" -Path ("/v1/tasks/{0}/hygiene-metadata" -f [Uri]::EscapeDataString($taskId)) -Body @{
      project_id = $ProjectId
      operation = "mark_keep_blocked"
      reason = "Goal 317 operator policy: keep blocked and excluded from worker scheduling."
    } | Out-Null
    $applied += New-Action -Kind "keep_blocked_or_archive" -TaskId $taskId -Operation "mark_keep_blocked" -Reason "Applied metadata only."
  }
  foreach ($taskId in $unsafeIds) {
    Invoke-SkyBridgeJson -Method "POST" -Path ("/v1/tasks/{0}/hygiene-metadata" -f [Uri]::EscapeDataString($taskId)) -Body @{
      project_id = $ProjectId
      operation = "mark_excluded_from_requeue"
      reason = "Goal 317 operator policy: excluded from requeue and worker scheduling."
    } | Out-Null
    $applied += New-Action -Kind "excluded_from_requeue" -TaskId $taskId -Operation "mark_excluded_from_requeue" -Reason "Applied metadata only."
  }
} else {
  $warnings.Add("preview_only_no_task_mutation") | Out-Null
}

$after = Get-TaskSnapshot -TaskIds $allPlannedIds
$unsafeAfter = @($after.tasks | Where-Object { $ForbiddenTaskStatuses -contains [string]$_.status })
if ($unsafeAfter.Count -gt 0) { $warnings.Add("active_task_status_detected_after") | Out-Null }
if ($after.project_control_state -notin @("paused", "unknown")) { $warnings.Add("project_control_not_paused_after") | Out-Null }

$report = [pscustomobject]@{
  schema = "skybridge.task_hygiene_apply.v1"
  ok = ($warnings -notcontains "active_task_status_detected_after" -and ($mode -eq "preview" -or $after.project_control_state -in @("paused", "unknown")))
  mode = $mode
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  before = $before
  planned_actions = $planned
  applied_actions = @($applied)
  after = $after
  residual_warnings = @($warnings.ToArray())
  recommended_next_safe_action = if ($mode -eq "preview") { "Review preview output only. Do not run live apply during PR development; keep start-one forbidden until Goal 318." } else { "Review metadata-only apply evidence and keep execution gates closed until Goal 318." }
  safety = [pscustomobject]@{
    preview_only = ($mode -eq "preview")
    apply_requires_confirmation = $true
    confirmation_string_matched = ($mode -eq "apply")
    fixed_task_ids_required = $true
    tasks_mutated = ($mode -eq "apply")
    metadata_only = $true
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    evidence_written = ($mode -eq "apply" -and $evidenceIds.Count -gt 0)
    codex_run_called = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    project_control_unpaused = $false
    start_one_called = $false
    run_until_hold_called = $false
    logs_included = $false
    prompts_included = $false
    hermes_responses_included = $false
    notification_payloads_included = $false
    token_printed = $false
  }
  token_printed = $false
}

if ($OutputJsonFile) {
  $dir = Split-Path -Parent $OutputJsonFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $OutputJsonFile -Encoding UTF8
}
if ($OutputMarkdownFile) {
  $dir = Split-Path -Parent $OutputMarkdownFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  @(
    "# Task Hygiene Apply"
    ""
    "- mode: $($report.mode)"
    "- ok: $($report.ok)"
    "- evidence_repair_actions: $(@($planned.evidence_repair_actions).Count)"
    "- archive_or_keep_blocked_actions: $(@($planned.archive_or_keep_blocked_actions).Count)"
    "- unsafe_to_requeue_exclusion_actions: $(@($planned.unsafe_to_requeue_exclusion_actions).Count)"
    "- next_safe_action: $($report.recommended_next_safe_action)"
    "- token_printed: false"
  ) -join "`n" | Set-Content -LiteralPath $OutputMarkdownFile -Encoding UTF8
}

if ($Json) {
  $report | ConvertTo-Json -Depth 40
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "OK:           $($report.ok)"
  "Evidence:     $(@($planned.evidence_repair_actions).Count)"
  "Blocked:      $(@($planned.archive_or_keep_blocked_actions).Count)"
  "Excluded:     $(@($planned.unsafe_to_requeue_exclusion_actions).Count)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
