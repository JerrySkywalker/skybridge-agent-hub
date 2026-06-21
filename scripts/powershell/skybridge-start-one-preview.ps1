[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureWorkersFile,
  [string]$FixtureHygieneFile,
  [string]$FixtureSecondGateFile
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
  param([string]$Text, [int]$MaxLength = 240)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Invoke-ChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
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

function Invoke-ReadOnlyApi {
  param([string]$Path)
  $config = [pscustomobject]@{ token_env_var = $TokenEnvVar; token_file = $TokenFile }
  Invoke-SkyBridgeApi -Method GET -Path $Path -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
}

function Get-SecondGate {
  if ($FixtureSecondGateFile) { return Read-JsonFile -Path $FixtureSecondGateFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-execution-second-gate-readiness.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

function Get-Hygiene {
  if ($FixtureHygieneFile) { return Read-JsonFile -Path $FixtureHygieneFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-task-hygiene-report.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

function Get-TaskList {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  $response = Invoke-ReadOnlyApi -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))"
  @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
}

function Get-WorkerList {
  if ($FixtureWorkersFile) {
    $fixture = Read-JsonFile -Path $FixtureWorkersFile
    return @((Get-Prop -Object $fixture -Name "workers" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  $response = Invoke-ReadOnlyApi -Path "/v1/workers"
  @((Get-Prop -Object $response -Name "workers" -Default @()) | Where-Object { $null -ne $_ })
}

function Add-Reason {
  param([System.Collections.Generic.List[string]]$Reasons, [string]$Reason)
  if (-not [string]::IsNullOrWhiteSpace($Reason) -and -not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Test-UnsafeSurface {
  param($Task)
  $risk = ([string](Get-Prop -Object $Task -Name "risk" -Default "")).ToLowerInvariant()
  $taskType = ([string](Get-Prop -Object $Task -Name "task_type" -Default "")).ToLowerInvariant()
  $title = ([string](Get-Prop -Object $Task -Name "title" -Default "")).ToLowerInvariant()
  $required = (@(Get-Prop -Object $Task -Name "required_capabilities" -Default @()) -join " ").ToLowerInvariant()
  $allowed = (@(Get-Prop -Object $Task -Name "allowed_paths" -Default @()) -join " ").ToLowerInvariant()
  $blocked = (@(Get-Prop -Object $Task -Name "blocked_paths" -Default @()) -join " ").ToLowerInvariant()
  $combined = "$risk $taskType $title $required $allowed $blocked"
  return ($risk -in @("active", "high", "blocked", "production") -or $combined -match "(deploy|production|secret|credential|cookie|token|server-root|server_config|server-config|openresty|authelia|1panel|github-settings|branch-protection|/opt/skybridge-agent-hub)")
}

function Get-MetadataExcluded {
  param($Task)
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  if ($null -eq $metadata) { return $false }
  if (Get-BoolProp -Object $metadata -Name "excluded_from_worker_scheduling") { return $true }
  if (Get-BoolProp -Object $metadata -Name "excluded_from_requeue") { return $true }
  $history = @((Get-Prop -Object $metadata -Name "history" -Default @()) | Where-Object { $null -ne $_ })
  foreach ($item in $history) {
    if (Get-BoolProp -Object $item -Name "excluded_from_requeue") { return $true }
    if ([string](Get-Prop -Object $item -Name "operation") -eq "mark_excluded_from_requeue") { return $true }
  }
  return $false
}

function Test-WorkerCapabilityMatch {
  param($Task, [array]$Workers)
  $required = @((Get-Prop -Object $Task -Name "required_capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ })
  if ($required.Count -eq 0) { return $true }
  foreach ($worker in @($Workers)) {
    $status = ([string](Get-Prop -Object $worker -Name "status" -Default "offline")).ToLowerInvariant()
    $enabled = Get-BoolProp -Object $worker -Name "enabled" -Default $true
    if (-not $enabled -or $status -ne "online") { continue }
    $caps = @((Get-Prop -Object $worker -Name "capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($caps.Count -eq 0 -or @($required | Where-Object { $caps -notcontains $_ }).Count -eq 0) { return $true }
  }
  return $false
}

function New-CandidateSummary {
  param($Task)
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
    status = [string](Get-Prop -Object $Task -Name "status" -Default "unknown")
    title = [string](Get-Prop -Object $Task -Name "title" -Default "")
    risk = [string](Get-Prop -Object $Task -Name "risk" -Default "not_reported")
    task_type = [string](Get-Prop -Object $Task -Name "task_type" -Default "not_reported")
    required_capabilities = @((Get-Prop -Object $Task -Name "required_capabilities" -Default @()) | ForEach-Object { [string]$_ })
    assigned_worker_id = Get-Prop -Object $Task -Name "assigned_worker_id"
  }
}

$secondGate = Get-SecondGate
$hygiene = Get-Hygiene
$tasks = Get-TaskList
$workers = Get-WorkerList

$unsafeIds = @{}
foreach ($item in @((Get-Prop -Object $hygiene -Name "unsafe_to_requeue_candidates" -Default @()) | Where-Object { $null -ne $_ })) {
  $id = [string](Get-Prop -Object $item -Name "task_id" -Default "")
  if ($id) { $unsafeIds[$id] = $true }
}
$blockedIds = @{}
foreach ($item in @((Get-Prop -Object $hygiene -Name "archive_or_keep_blocked_candidates" -Default @()) | Where-Object { $null -ne $_ })) {
  $id = [string](Get-Prop -Object $item -Name "task_id" -Default "")
  if ($id) { $blockedIds[$id] = $true }
}

$eligible = New-Object System.Collections.Generic.List[object]
$excluded = New-Object System.Collections.Generic.List[object]
$reasonCounts = @{}
$goalResidueEligible = 0

foreach ($task in @($tasks)) {
  $taskId = [string](Get-Prop -Object $task -Name "task_id" -Default "")
  $status = ([string](Get-Prop -Object $task -Name "status" -Default "queued")).ToLowerInvariant()
  $risk = ([string](Get-Prop -Object $task -Name "risk" -Default "not_reported")).ToLowerInvariant()
  $reasons = [System.Collections.Generic.List[string]]::new()

  if ($status -ne "queued") {
    if ($status -eq "failed") { Add-Reason $reasons "failed_status" }
    elseif ($status -eq "blocked") { Add-Reason $reasons "blocked_historical_status" }
    elseif ($status -eq "completed") { Add-Reason $reasons "completed_status" }
    else { Add-Reason $reasons "not_queued" }
  }
  if (Get-MetadataExcluded -Task $task) { Add-Reason $reasons "hygiene_metadata_excluded_from_worker_scheduling" }
  if ($unsafeIds.ContainsKey($taskId)) { Add-Reason $reasons "unsafe_to_requeue" }
  if ($blockedIds.ContainsKey($taskId)) { Add-Reason $reasons "blocked_historical_task" }
  if ($risk -ne "low") { Add-Reason $reasons "risk_not_low" }
  if (Test-UnsafeSurface -Task $task) { Add-Reason $reasons "unsafe_policy_surface" }
  $hygieneStatus = [string](Get-Prop -Object $task -Name "task_hygiene_status" -Default "")
  if ($hygieneStatus -in @("pr_merged_needs_evidence", "failed_unrecovered", "blocked_historical", "stale_claim", "stale_running", "lease_missing", "lease_expired")) {
    Add-Reason $reasons "blocked_hygiene_status"
  }
  $lease = Get-Prop -Object $task -Name "lease"
  if ($null -ne $lease -and ([string](Get-Prop -Object $lease -Name "lease_status" -Default "active")) -eq "active") {
    Add-Reason $reasons "active_lease_conflict"
  }
  $assignedWorker = [string](Get-Prop -Object $task -Name "assigned_worker_id" -Default "")
  if (-not [string]::IsNullOrWhiteSpace($assignedWorker)) {
    $assigned = @($workers | Where-Object { [string](Get-Prop -Object $_ -Name "worker_id" -Default "") -eq $assignedWorker })
    if ($assigned.Count -gt 0 -and ([string](Get-Prop -Object $assigned[0] -Name "status" -Default "offline")).ToLowerInvariant() -ne "online") {
      Add-Reason $reasons "assigned_legacy_worker_offline"
    }
  }
  if (-not (Test-WorkerCapabilityMatch -Task $task -Workers $workers)) { Add-Reason $reasons "worker_capability_mismatch" }

  if ($reasons.Count -eq 0) {
    if ($taskId -match "(?i)(goal-31[57]|315|317|remote-docs-exec-pilot-001)") { $goalResidueEligible += 1 }
    $eligible.Add((New-CandidateSummary -Task $task)) | Out-Null
  } else {
    foreach ($reason in @($reasons.ToArray())) {
      if (-not $reasonCounts.ContainsKey($reason)) { $reasonCounts[$reason] = 0 }
      $reasonCounts[$reason] += 1
    }
    $excluded.Add([pscustomobject]@{
      task_id = $taskId
      status = [string](Get-Prop -Object $task -Name "status" -Default "unknown")
      reasons = @($reasons.ToArray())
    }) | Out-Null
  }
}

$selected = $null
if ($eligible.Count -gt 0 -and (Get-BoolProp -Object $secondGate -Name "allowed_preview_only") -and -not (Get-BoolProp -Object $secondGate -Name "allowed_execution")) {
  $selected = @($eligible.ToArray() | Sort-Object -Property task_id | Select-Object -First 1)[0]
}

$status = if ($null -eq $selected) { "no_safe_candidate" } else { "candidate_previewed" }
if (-not (Get-BoolProp -Object $secondGate -Name "allowed_preview_only")) { $status = "second_gate_preview_blocked" }

$reasonObjects = @($reasonCounts.Keys | Sort-Object | ForEach-Object {
  [pscustomobject]@{ reason = [string]$_; count = [int]$reasonCounts[$_] }
})

$remoteDocs = @($excluded | Where-Object { $_.task_id -eq "remote-docs-exec-pilot-001" })

$report = [pscustomobject]@{
  schema = "skybridge.start_one_preview.v1"
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  status = $status
  preview_only = $true
  would_claim = $false
  would_run_codex = $false
  would_unpause_project_control = $false
  selected_candidate = $selected
  candidate_pool_summary = [pscustomobject]@{
    total_tasks = @($tasks).Count
    queued_tasks = @($tasks | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "queued" }).Count
    eligible_candidates = $eligible.Count
    excluded_tasks = $excluded.Count
    online_workers = @($workers | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "offline")).ToLowerInvariant() -eq "online" }).Count
  }
  excluded_tasks_summary = [pscustomobject]@{
    failed_tasks_excluded = @($excluded | Where-Object { $_.reasons -contains "failed_status" }).Count
    blocked_historical_tasks_excluded = @($excluded | Where-Object { $_.reasons -contains "blocked_historical_status" -or $_.reasons -contains "blocked_historical_task" }).Count
    hygiene_metadata_excluded_tasks = @($excluded | Where-Object { $_.reasons -contains "hygiene_metadata_excluded_from_worker_scheduling" }).Count
    unsafe_to_requeue_tasks_excluded = @($excluded | Where-Object { $_.reasons -contains "unsafe_to_requeue" }).Count
    completed_tasks_excluded = @($excluded | Where-Object { $_.reasons -contains "completed_status" }).Count
    remote_docs_exec_pilot_001_excluded = ($remoteDocs.Count -gt 0)
    goal_315_317_residue_eligible = $goalResidueEligible
  }
  exclusion_reasons = @($reasonObjects)
  excluded_tasks = @($excluded.ToArray())
  second_gate = [pscustomobject]@{
    status = [string](Get-Prop -Object $secondGate -Name "status" -Default "unknown")
    allowed_preview_only = Get-BoolProp -Object $secondGate -Name "allowed_preview_only"
    allowed_execution = Get-BoolProp -Object $secondGate -Name "allowed_execution"
    project_control_state = [string](Get-Prop -Object $secondGate -Name "project_control_state" -Default "unknown")
    hermes_tool_execution_risk = Get-BoolProp -Object $secondGate -Name "hermes_tool_execution_risk"
    second_gate_configured = Get-BoolProp -Object $secondGate -Name "second_gate_configured"
  }
  forbidden_actions = [pscustomobject]@{
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    codex_run_called = $false
    queue_apply_called = $false
    project_control_unpaused = $false
    start_one_called = $false
    run_until_hold_called = $false
  }
  recommended_next_safe_action = if ($status -eq "no_safe_candidate") {
    "No safe queued low-risk candidate exists. Keep project_control paused and do not claim tasks."
  } elseif ($status -eq "second_gate_preview_blocked") {
    "Fix second-gate preview blockers before reviewing any start-one candidate."
  } else {
    "Review the selected candidate only. Goal 318 forbids claim, Codex execution, and project_control unpause."
  }
  safety = [pscustomobject]@{
    read_only = $true
    raw_logs_included = $false
    prompt_content_included = $false
    tasks_claimed = $false
    tasks_requeued = $false
    codex_run_called = $false
    token_printed = $false
  }
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 40
} else {
  "Schema:       $($report.schema)"
  "Status:       $($report.status)"
  "PreviewOnly:  true"
  "WouldClaim:   false"
  "WouldCodex:   false"
  "Candidates:   eligible=$($report.candidate_pool_summary.eligible_candidates) excluded=$($report.candidate_pool_summary.excluded_tasks)"
  "Selected:     $(if ($report.selected_candidate) { $report.selected_candidate.task_id } else { 'none' })"
  "UnsafeExcl:   $($report.excluded_tasks_summary.unsafe_to_requeue_tasks_excluded)"
  "BlockedExcl:  $($report.excluded_tasks_summary.blocked_historical_tasks_excluded)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
