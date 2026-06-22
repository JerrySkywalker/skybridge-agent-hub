[CmdletBinding(DefaultParameterSetName = "Preview")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [Parameter(ParameterSetName = "Preview")][switch]$Preview,
  [Parameter(ParameterSetName = "Apply")][switch]$Apply,
  [string]$Confirm,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureWorkersFile,
  [string]$FixtureHygieneFile,
  [string]$FixtureSecondGateFile,
  [string]$FixtureStateDir,
  [switch]$FixtureCodexSuccess,
  [switch]$FixtureCodexFailure,
  [switch]$FixtureCodexUnavailable,
  [switch]$FixtureCodexNonZero,
  [switch]$FixtureCodexUnsafePath,
  [switch]$FixtureCodexNoChange,
  [switch]$FixtureEvidenceWriteFailure,
  [switch]$FixtureValidationFailure,
  [switch]$FixtureCompleteApiUnexpectedResponse,
  [switch]$FixtureFailApiUnexpectedResponse,
  [switch]$FixtureWorkerHeartbeatExpiredBeforeClaim,
  [switch]$FixtureWorkerHeartbeatExpiredAfterClaim,
  [switch]$FixtureTaskStatusMismatchAfterClaim
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$PilotTaskId = "start-one-apply-pilot-docs-001"
$WorkerId = "jerry-win-local-01"
$AllowedPath = "docs/operations/START_ONE_APPLY_PILOT.md"
$ConfirmText = "I_UNDERSTAND_START_ONE_SINGLE_SAFE_TASK_ONLY"
$Mode = if ($Apply) { "apply" } else { "preview" }
$EvidenceDir = if ($FixtureStateDir) { $FixtureStateDir } else { Join-Path $RepoRoot ".agent\tmp\start-one-apply-pilot" }
$EvidencePath = Join-Path $EvidenceDir "start-one-apply-pilot-evidence.json"
$ExecutionAttemptId = "start-one-pilot-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"

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

function Get-StatusText {
  param($Object, [string]$Default = "")
  ([string](Get-Prop -Object $Object -Name "status" -Default $Default)).ToLowerInvariant()
}

function Test-TaskFailedWithEvidence {
  param($Task)
  if ($null -eq $Task) { return $false }
  $status = Get-StatusText -Object $Task
  $result = Get-Prop -Object $Task -Name "result"
  $evidence = Get-Prop -Object $result -Name "evidence_summary"
  $final = [string](Get-Prop -Object $evidence -Name "final_task_status" -Default (Get-Prop -Object $result -Name "final_task_status" -Default ""))
  $terminal = [string](Get-Prop -Object $evidence -Name "terminal_state" -Default (Get-Prop -Object $result -Name "terminal_state" -Default ""))
  return ($status -in @("failed", "failed_with_evidence") -and ($final -eq "failed_with_evidence" -or $terminal -eq "failed_with_evidence" -or $terminal -eq "already_failed_with_evidence_noop" -or (Get-BoolProp -Object $evidence -Name "evidence_present" -Default $false)))
}

function Get-PilotTerminalNoop {
  param($Task)
  if ($null -eq $Task) { return $null }
  if ([string](Get-Prop -Object $Task -Name "task_id" -Default "") -ne $PilotTaskId) { return $null }
  $status = Get-StatusText -Object $Task
  if ($status -eq "completed") {
    return [pscustomobject]@{
      status = "terminal_completed"
      terminal_state = "already_completed_noop"
      final_task_status = "completed"
      hold_reason = "pilot_task_already_completed"
      failure_category = $null
      manual_operator_review_needed = $false
    }
  }
  if (Test-TaskFailedWithEvidence -Task $Task) {
    return [pscustomobject]@{
      status = "terminal_failed_with_evidence"
      terminal_state = "already_failed_with_evidence_noop"
      final_task_status = "failed_with_evidence"
      hold_reason = "pilot_task_already_failed_with_evidence"
      failure_category = "already_failed_with_evidence_noop"
      manual_operator_review_needed = $true
    }
  }
  return $null
}

function Get-ClaimLeaseState {
  param($Task)
  $assigned = [string](Get-Prop -Object $Task -Name "assigned_worker_id" -Default "")
  $claimId = [string](Get-Prop -Object $Task -Name "claim_id" -Default "")
  $lease = Get-Prop -Object $Task -Name "lease"
  $leaseId = [string](Get-Prop -Object $lease -Name "lease_id" -Default (Get-Prop -Object $Task -Name "lease_id" -Default ""))
  $expiresRaw = [string](Get-Prop -Object $lease -Name "expires_at" -Default (Get-Prop -Object $Task -Name "lease_expires_at" -Default ""))
  $hasClaim = (-not [string]::IsNullOrWhiteSpace($assigned) -and $assigned -ne "-" -and $assigned -ne $WorkerId) -or -not [string]::IsNullOrWhiteSpace($claimId)
  $hasLease = -not [string]::IsNullOrWhiteSpace($leaseId) -or -not [string]::IsNullOrWhiteSpace($expiresRaw)
  $staleLease = $false
  if ($hasLease -and -not [string]::IsNullOrWhiteSpace($expiresRaw)) {
    try { $staleLease = ([datetimeoffset]::Parse($expiresRaw).UtcDateTime -lt (Get-Date).ToUniversalTime()) } catch {}
  }
  [pscustomobject]@{
    claimed = $hasClaim
    active_lease = ($hasLease -and -not $staleLease)
    stale_lease = ($hasLease -and $staleLease)
    claim_id = if ($claimId) { "reported" } else { $null }
    lease_id = if ($leaseId) { "reported" } else { $null }
  }
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

function Get-TaskList {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
}

function Get-DirectPilotTask {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId } | Select-Object -First 1)
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return $null }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($PilotTaskId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return (Get-Prop -Object $response -Name "task" -Default $response)
  } catch {
    return $null
  }
}

function Get-WorkerList {
  if ($FixtureWorkersFile) {
    $fixture = Read-JsonFile -Path $FixtureWorkersFile
    return @((Get-Prop -Object $fixture -Name "workers" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
  @((Get-Prop -Object $response -Name "workers" -Default @()) | Where-Object { $null -ne $_ })
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
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
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
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-ChildJson -Arguments $args -AllowNonZero
}

function Test-WorkerMatch {
  param([array]$Workers, $Task)
  $worker = @($Workers | Where-Object { [string](Get-Prop -Object $_ -Name "worker_id") -eq $WorkerId } | Select-Object -First 1)
  if ($worker.Count -lt 1) { return $false }
  $status = ([string](Get-Prop -Object $worker[0] -Name "status" -Default "offline")).ToLowerInvariant()
  $enabled = Get-BoolProp -Object $worker[0] -Name "enabled" -Default $true
  $caps = @((Get-Prop -Object $worker[0] -Name "capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if (-not ($enabled -and $status -eq "online")) { return $false }
  $required = @((Get-Prop -Object $Task -Name "required_capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $allowedWorker = [string](Get-Prop -Object $metadata -Name "allowed_worker_id" -Default "")
  $taskCarriesDocsProof = ($required -contains "codex" -and ($required -contains "docs" -or $required -contains "documentation") -and $required -contains "windows")
  $explicitWorkerProof = ($taskCarriesDocsProof -and ([string]::IsNullOrWhiteSpace($allowedWorker) -or $allowedWorker -eq $WorkerId))
  if ($caps.Count -gt 0) {
    if ($caps.Count -eq 1 -and $caps -contains "heartbeat") { return $explicitWorkerProof }
    return ($caps -contains "codex" -and ($caps -contains "docs" -or $caps -contains "documentation"))
  }
  return $explicitWorkerProof
}

function Test-SafePilotCandidate {
  param($Task, [array]$Workers, $HygieneTask)
  $reasons = [System.Collections.Generic.List[string]]::new()
  $taskId = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
  $status = ([string](Get-Prop -Object $Task -Name "status" -Default "")).ToLowerInvariant()
  $risk = ([string](Get-Prop -Object $Task -Name "risk" -Default "")).ToLowerInvariant()
  $taskType = ([string](Get-Prop -Object $Task -Name "task_type" -Default "")).ToLowerInvariant()
  $allowed = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  $text = (@(
    Get-Prop -Object $Task -Name "title" -Default ""
    Get-Prop -Object $Task -Name "body" -Default ""
    Get-Prop -Object $Task -Name "prompt_summary" -Default ""
    @($allowed) -join " "
  ) -join " ").ToLowerInvariant()
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $claimLease = Get-ClaimLeaseState -Task $Task
  $safeMarker = Get-BoolProp -Object $metadata -Name "safe_start_one_pilot" -Default $false
  $hygieneStatus = ([string](Get-Prop -Object $HygieneTask -Name "hygiene_status" -Default "")).ToLowerInvariant()
  $hygieneClass = ([string](Get-Prop -Object $HygieneTask -Name "classification" -Default "")).ToLowerInvariant()
  $hygienePilotProof = ($safeMarker -and $hygieneStatus -eq "active_ok" -and $hygieneClass -eq "not-residue")
  $riskOk = ($risk -eq "low" -or ($risk -in @("", "not_reported") -and $hygienePilotProof))
  if ($taskId -ne $PilotTaskId) { $reasons.Add("task_id_not_pilot") | Out-Null }
  if ($status -ne "queued") { $reasons.Add("${status}_status") | Out-Null }
  if (-not $riskOk) { $reasons.Add("risk_not_low") | Out-Null }
  if ($taskType -notin @("docs", "test")) { $reasons.Add("task_type_not_docs_or_test") | Out-Null }
  if ($allowed.Count -ne 1 -or $allowed[0] -ne $AllowedPath) { $reasons.Add("allowed_paths_not_pilot_only") | Out-Null }
  if ($claimLease.claimed) { $reasons.Add("duplicate_claim_rejected") | Out-Null }
  if ($claimLease.active_lease) { $reasons.Add("active_lease_present") | Out-Null }
  if ($claimLease.stale_lease) { $reasons.Add("claim_expired") | Out-Null }
  if ($text -match "(deploy|production|secret|credential|cookie|server-root|openresty|authelia|cloudflare|dns|github settings|branch protection|/opt/skybridge-agent-hub)") { $reasons.Add("unsafe_policy_surface") | Out-Null }
  if (Get-BoolProp -Object $metadata -Name "excluded_from_worker_scheduling" -Default $false) { $reasons.Add("unsafe_hygiene_metadata") | Out-Null }
  if (-not (Test-WorkerMatch -Workers $Workers -Task $Task)) { $reasons.Add("worker_capability_mismatch") | Out-Null }
  [pscustomobject]@{ safe = ($reasons.Count -eq 0); reasons = @($reasons.ToArray()) }
}

function Get-HygienePilotTask {
  param($Hygiene)
  @((Get-Prop -Object $Hygiene -Name "task_classifications" -Default @()) | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId } | Select-Object -First 1)
}

function Test-PilotSourceMismatch {
  param($DirectTask, [array]$ListTasks)
  $mismatches = [System.Collections.Generic.List[string]]::new()
  if ($null -eq $DirectTask) { return @($mismatches.ToArray()) }
  foreach ($listTask in @($ListTasks)) {
    foreach ($field in @("status", "project_id", "task_type")) {
      $directValue = [string](Get-Prop -Object $DirectTask -Name $field -Default "")
      $listValue = [string](Get-Prop -Object $listTask -Name $field -Default "")
      if ($directValue -and $listValue -and $directValue -ne $listValue) { $mismatches.Add("${field}_mismatch") | Out-Null }
    }
    $directAllowed = @((Get-Prop -Object $DirectTask -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
    $listAllowed = @((Get-Prop -Object $listTask -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
    if (($directAllowed -join "|") -ne ($listAllowed -join "|")) { $mismatches.Add("allowed_paths_mismatch") | Out-Null }
  }
  @($mismatches.ToArray() | Select-Object -Unique)
}

function New-PilotTaskLookup {
  param($DirectTask, [array]$ListTasks, $HygieneTask, [array]$Workers, [array]$Rejections)
  $task = if ($DirectTask) { $DirectTask } elseif (@($ListTasks).Count -eq 1) { @($ListTasks)[0] } else { $null }
  [pscustomobject]@{
    found_by_id = ($null -ne $DirectTask)
    found_in_task_list = (@($ListTasks).Count -gt 0)
    found_in_hygiene = ($null -ne $HygieneTask)
    task_id = if ($task) { [string](Get-Prop -Object $task -Name "task_id" -Default "") } else { $PilotTaskId }
    status = if ($task) { [string](Get-Prop -Object $task -Name "status" -Default "not_reported") } elseif ($HygieneTask) { [string](Get-Prop -Object $HygieneTask -Name "status" -Default "not_reported") } else { "not_reported" }
    risk = if ($task) { [string](Get-Prop -Object $task -Name "risk" -Default "not_reported") } elseif ($HygieneTask) { [string](Get-Prop -Object $HygieneTask -Name "risk" -Default "not_reported") } else { "not_reported" }
    task_type = if ($task) { [string](Get-Prop -Object $task -Name "task_type" -Default "not_reported") } elseif ($HygieneTask) { [string](Get-Prop -Object $HygieneTask -Name "task_type" -Default "not_reported") } else { "not_reported" }
    allowed_paths = if ($task) { @((Get-Prop -Object $task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") }) } else { @() }
    required_capabilities = if ($task) { @((Get-Prop -Object $task -Name "required_capabilities" -Default @()) | ForEach-Object { [string]$_ }) } else { @() }
    worker_match = if ($task) { Test-WorkerMatch -Workers $Workers -Task $task } else { $false }
    rejection_reasons = @($Rejections | ForEach-Object { $_.reasons } | ForEach-Object { [string]$_ } | Select-Object -Unique)
    token_printed = $false
  }
}

function Get-ResidueProof {
  param([array]$Tasks, $Hygiene)
  $unsafeIds = @{}
  foreach ($item in @((Get-Prop -Object $Hygiene -Name "unsafe_to_requeue_candidates" -Default @()) | Where-Object { $null -ne $_ })) {
    $id = [string](Get-Prop -Object $item -Name "task_id" -Default "")
    if ($id) { $unsafeIds[$id] = $true }
  }
  $blockedIds = @{}
  foreach ($item in @((Get-Prop -Object $Hygiene -Name "archive_or_keep_blocked_candidates" -Default @()) | Where-Object { $null -ne $_ })) {
    $id = [string](Get-Prop -Object $item -Name "task_id" -Default "")
    if ($id) { $blockedIds[$id] = $true }
  }
  $remote = @($Tasks | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq "remote-docs-exec-pilot-001" })
  $goalResidueEligible = @($Tasks | Where-Object {
    $id = [string](Get-Prop -Object $_ -Name "task_id")
    $id -match "(?i)(goal-31[57]|315|317|remote-docs-exec-pilot-001)" -and $id -eq $PilotTaskId
  }).Count
  [pscustomobject]@{
    unsafe_to_requeue_tasks_excluded = [int]$unsafeIds.Count
    blocked_historical_tasks_excluded = [int]$blockedIds.Count
    remote_docs_exec_pilot_001_excluded = ($remote.Count -gt 0)
    completed_tasks_excluded = @($Tasks | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "completed" }).Count
    goal_315_317_residue_eligible = $goalResidueEligible
    no_old_residue_eligible = ($goalResidueEligible -eq 0)
    no_old_task_claimed = $true
    no_old_task_requeued = $true
  }
}

function New-CandidateSummary {
  param($Task)
  if ($null -eq $Task) { return $null }
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
    status = [string](Get-Prop -Object $Task -Name "status" -Default "")
    risk = [string](Get-Prop -Object $Task -Name "risk" -Default "")
    task_type = [string](Get-Prop -Object $Task -Name "task_type" -Default "")
    allowed_paths = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { [string]$_ })
    selected_worker_id = $WorkerId
  }
}

function Write-Evidence {
  param(
    [string]$Status,
    [string]$TerminalState = $Status,
    [string]$FailureCategory = "",
    [string[]]$FilesChanged,
    [string[]]$AllowedPaths = @($AllowedPath),
    [string[]]$ValidationCommands,
    $ValidationResult = $null,
    [string]$Summary,
    [bool]$NoOldResidueSelected,
    $ClaimResult = $null
  )
  if ($FixtureEvidenceWriteFailure) {
    return [pscustomobject]@{
      ok = $false
      evidence_written = $false
      evidence_path = $EvidencePath
      failure_category = "evidence_write_failed"
      terminal_state = "evidence_write_failed"
      token_printed = $false
    }
  }
  New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
  $evidence = [pscustomobject]@{
    schema = "skybridge.start_one_apply_pilot_evidence.v2"
    task_id = $PilotTaskId
    selected_worker_id = $WorkerId
    execution_attempt_id = $ExecutionAttemptId
    claim_id = if ($ClaimResult) { Get-Prop -Object $ClaimResult -Name "claim_id" -Default (Get-Prop -Object $ClaimResult -Name "claim_status" -Default "reported") } else { $null }
    status = $Status
    final_task_status = $Status
    terminal_state = $TerminalState
    failure_category = if ([string]::IsNullOrWhiteSpace($FailureCategory)) { $null } else { $FailureCategory }
    files_changed = @($FilesChanged)
    allowed_paths = @($AllowedPaths)
    validation_commands = @($ValidationCommands)
    validation_result = if ($ValidationResult) { $ValidationResult } else { [pscustomobject]@{ ok = ($Status -eq "completed"); status = if ($Status -eq "completed") { "passed" } else { "not_run" }; token_printed = $false } }
    execution_summary = ConvertTo-SafeText -Text $Summary -MaxLength 260
    safety = [pscustomobject]@{
      no_old_residue_selected = $NoOldResidueSelected
      old_residue_selected = $false
      prompt_content_included = $false
      log_content_included = $false
      credential_values_included = $false
      deployment_run = $false
      server_runtime_mutated = $false
      github_settings_touched = $false
      run_until_hold_called = $false
      project_control_unpaused = $false
      token_printed = $false
    }
    token_printed = $false
  }
  $evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
  [pscustomobject]@{ ok = $true; evidence_written = $true; evidence_path = $EvidencePath; evidence = $evidence; token_printed = $false }
}

function Invoke-PilotCodexOnce {
  if ($FixtureCodexUnavailable) {
    return [pscustomobject]@{ ok = $false; failure_category = "codex_cli_unavailable"; terminal_state = "failed_needs_operator_review"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); summary = "Codex CLI unavailable; failed closed."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexNonZero) {
    return [pscustomobject]@{ ok = $false; failure_category = "codex_nonzero"; terminal_state = "failed_with_evidence"; codex_run_called = $true; codex_execution_count = 1; files_changed = @(); summary = "Fixture Codex execution returned nonzero."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexUnsafePath) {
    return [pscustomobject]@{ ok = $false; failure_category = "unsafe_path_changed"; terminal_state = "unsafe_path_changed"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($AllowedPath, "scripts/powershell/unsafe-fixture.ps1"); summary = "Fixture Codex execution changed an unsafe path."; validation_commands = @("fixture-path-guard"); validation_result = [pscustomobject]@{ ok = $false; status = "unsafe_path_changed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexNoChange) {
    return [pscustomobject]@{ ok = $false; failure_category = "no_file_changed"; terminal_state = "validation_failed"; codex_run_called = $true; codex_execution_count = 1; files_changed = @(); summary = "Fixture Codex execution changed no files."; validation_commands = @("fixture-path-guard"); validation_result = [pscustomobject]@{ ok = $false; status = "no_file_changed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureValidationFailure) {
    return [pscustomobject]@{ ok = $false; failure_category = "validation_failed"; terminal_state = "validation_failed"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($AllowedPath); summary = "Fixture validation failed after docs-only Codex execution."; validation_commands = @("fixture-validation"); validation_result = [pscustomobject]@{ ok = $false; status = "failed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexFailure) {
    return [pscustomobject]@{ ok = $false; failure_category = "codex_nonzero"; terminal_state = "failed_with_evidence"; codex_run_called = $true; codex_execution_count = 1; files_changed = @(); summary = "Fixture Codex execution failed safely."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexSuccess) {
    return [pscustomobject]@{ ok = $true; failure_category = $null; terminal_state = "completed_with_evidence"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($AllowedPath); summary = "Fixture Codex execution updated the pilot docs evidence path."; validation_commands = @("fixture-validation"); validation_result = [pscustomobject]@{ ok = $true; status = "passed"; token_printed = $false }; token_printed = $false }
  }
  $codex = Get-Command codex -ErrorAction SilentlyContinue
  if ($null -eq $codex) {
    return [pscustomobject]@{ ok = $false; failure_category = "codex_cli_unavailable"; terminal_state = "failed_needs_operator_review"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); summary = "Codex CLI unavailable; failed closed after the single pilot claim."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  $before = @(& git status --short)
  $prompt = @"
Update only docs/operations/START_ONE_APPLY_PILOT.md for SkyBridge Mega Goal 319.
Write a concise operations note proving the one-task start-one apply pilot boundary.
Do not edit code, scripts, secrets, deployment files, GitHub settings, or infrastructure.
"@
  $null = & codex exec --sandbox workspace-write $prompt 2>$null
  $exitCode = $LASTEXITCODE
  $after = @(& git status --short)
  $changed = @($after | Where-Object { $before -notcontains $_ } | ForEach-Object {
    $line = [string]$_
    if ($line.Length -gt 3) { $line.Substring(3).Replace("\", "/") }
  } | Where-Object { $_ })
  $unsafe = @($changed | Where-Object { $_ -ne $AllowedPath })
  if ($exitCode -ne 0 -or $unsafe.Count -gt 0 -or $changed.Count -lt 1) {
    $category = if ($unsafe.Count -gt 0) { "unsafe_path_changed" } elseif ($changed.Count -lt 1) { "no_file_changed" } else { "codex_nonzero" }
    $terminal = if ($category -eq "unsafe_path_changed") { "unsafe_path_changed" } elseif ($category -eq "no_file_changed") { "validation_failed" } else { "failed_with_evidence" }
    return [pscustomobject]@{ ok = $false; failure_category = $category; terminal_state = $terminal; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); summary = "Codex execution failed or changed an unexpected path."; validation_commands = @("git diff --name-only"); validation_result = [pscustomobject]@{ ok = $false; status = $category; token_printed = $false }; token_printed = $false }
  }
  [pscustomobject]@{ ok = $true; failure_category = $null; terminal_state = "completed_with_evidence"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); summary = "Codex execution completed the docs-only pilot update."; validation_commands = @("git diff --name-only"); validation_result = [pscustomobject]@{ ok = $true; status = "passed"; token_printed = $false }; token_printed = $false }
}

function New-Report {
  param(
    [bool]$Ok,
    [string]$Status,
    $SelectedTask,
    $ClaimResult,
    $ExecutionResult,
    $EvidenceResult,
    [string]$FinalTaskStatus,
    $OldResidueExclusion,
    $PilotTaskLookup,
    [string]$TerminalState = "",
    [string]$HoldReason = "",
    [string]$FailureCategory = "",
    [bool]$ManualOperatorReviewNeeded = $false,
    [string[]]$Blockers = @()
  )
  $evidenceSummary = if ($EvidenceResult -and (Get-Prop -Object $EvidenceResult -Name "evidence")) {
    $ev = Get-Prop -Object $EvidenceResult -Name "evidence"
    [pscustomobject]@{
      evidence_present = Get-BoolProp -Object $EvidenceResult -Name "evidence_written" -Default (Get-BoolProp -Object $EvidenceResult -Name "ok")
      schema = [string](Get-Prop -Object $ev -Name "schema" -Default "")
      terminal_state = [string](Get-Prop -Object $ev -Name "terminal_state" -Default $TerminalState)
      failure_category = Get-Prop -Object $ev -Name "failure_category"
      files_changed = @((Get-Prop -Object $ev -Name "files_changed" -Default @()) | ForEach-Object { [string]$_ })
      allowed_paths = @((Get-Prop -Object $ev -Name "allowed_paths" -Default @()) | ForEach-Object { [string]$_ })
      prompt_content_included = $false
      log_content_included = $false
      credential_values_included = $false
      token_printed = $false
    }
  } else {
    [pscustomobject]@{
      evidence_present = Get-BoolProp -Object $EvidenceResult -Name "evidence_written" -Default $false
      terminal_state = if ($TerminalState) { $TerminalState } else { $FinalTaskStatus }
      failure_category = if ($FailureCategory) { $FailureCategory } else { $null }
      files_changed = @()
      allowed_paths = @($AllowedPath)
      prompt_content_included = $false
      log_content_included = $false
      credential_values_included = $false
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.start_one_apply_pilot.v1"
    ok = $Ok
    mode = $Mode
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    project_id = $ProjectId
    status = $Status
    selected_task_id = if ($SelectedTask) { [string](Get-Prop -Object $SelectedTask -Name "task_id" -Default "") } else { $null }
    selected_candidate = New-CandidateSummary -Task $SelectedTask
    would_claim = ($Mode -eq "apply" -and $null -ne $SelectedTask)
    would_run_codex = ($Mode -eq "apply" -and $null -ne $SelectedTask)
    would_unpause_project_control = $false
    claim_result = $ClaimResult
    execution_result = $ExecutionResult
    evidence_result = $EvidenceResult
    final_task_status = $FinalTaskStatus
    terminal_state = if ($TerminalState) { $TerminalState } else { $FinalTaskStatus }
    hold_reason = if ($HoldReason) { $HoldReason } else { $null }
    failure_category = if ($FailureCategory) { $FailureCategory } else { $null }
    execution_attempt_id = $ExecutionAttemptId
    manual_operator_review_needed = $ManualOperatorReviewNeeded
    evidence_summary = $evidenceSummary
    pilot_task_lookup = $PilotTaskLookup
    old_residue_exclusion = $OldResidueExclusion
    project_control = [pscustomobject]@{
      state = "paused"
      project_control_unpaused = $false
      temporary_internal_claim_path = ($Mode -eq "apply")
      campaign_metadata_advanced = $false
    }
    forbidden_actions = [pscustomobject]@{
      batch_execution_implemented = $false
      run_until_hold_implemented = $false
      run_until_hold_called = $false
      old_task_claimed = $false
      old_task_requeued = $false
      project_control_unpaused = $false
      deployment_run = $false
      secrets_mutated = $false
      server_root_mutated = $false
      external_infrastructure_changed = $false
      github_settings_changed = $false
    }
    safety = [pscustomobject]@{
      preview_default = $true
      apply_requires_exact_confirmation = $true
      max_selected_tasks = 1
      max_claims = if ($Mode -eq "apply") { 1 } else { 0 }
      max_codex_runs = if ($Mode -eq "apply") { 1 } else { 0 }
      would_claim = ($Mode -eq "apply" -and $Ok -and $null -ne $SelectedTask)
      would_run_codex = ($Mode -eq "apply" -and $Ok -and $null -ne $SelectedTask)
      would_unpause_project_control = $false
      token_printed = $false
    }
    blockers = @($Blockers)
    token_printed = $false
  }
}

$directPilotTask = Get-DirectPilotTask
$tasks = Get-TaskList
$workers = Get-WorkerList
$hygiene = Get-Hygiene
$secondGate = Get-SecondGate
$oldResidue = Get-ResidueProof -Tasks $tasks -Hygiene $hygiene
$pilotCandidates = @($tasks | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId })
if ($directPilotTask -and @($pilotCandidates).Count -eq 0) { $pilotCandidates = @($directPilotTask) }
$hygienePilotTask = Get-HygienePilotTask -Hygiene $hygiene
$safeCandidates = @()
$candidateRejections = @()
foreach ($candidate in @($pilotCandidates)) {
  $decision = Test-SafePilotCandidate -Task $candidate -Workers $workers -HygieneTask $hygienePilotTask
  if ($decision.safe) {
    $safeCandidates += $candidate
  } else {
    $candidateRejections += [pscustomobject]@{ task_id = $PilotTaskId; reasons = @($decision.reasons) }
  }
}
$sourceMismatches = Test-PilotSourceMismatch -DirectTask $directPilotTask -ListTasks @($tasks | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId })
$pilotTaskLookup = New-PilotTaskLookup -DirectTask $directPilotTask -ListTasks @($tasks | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId }) -HygieneTask $hygienePilotTask -Workers $workers -Rejections $candidateRejections

$blockers = [System.Collections.Generic.List[string]]::new()
if (@($safeCandidates).Count -eq 0) { $blockers.Add("no_safe_pilot_task") | Out-Null }
if (@($safeCandidates).Count -gt 1) { $blockers.Add("multiple_candidates_selected") | Out-Null }
foreach ($mismatch in @($sourceMismatches)) { $blockers.Add("pilot_lookup_source_$mismatch") | Out-Null }
if ([string](Get-Prop -Object $secondGate -Name "project_control_state" -Default "paused") -ne "paused") { $blockers.Add("project_control_not_paused") | Out-Null }
if (-not (Get-BoolProp -Object $secondGate -Name "allowed_preview_only" -Default $true)) { $blockers.Add("second_gate_preview_not_ready") | Out-Null }
if (Get-BoolProp -Object $secondGate -Name "allowed_execution" -Default $false) { $blockers.Add("second_gate_unexpectedly_allows_general_execution") | Out-Null }
if (-not [bool]$oldResidue.no_old_residue_eligible) { $blockers.Add("old_residue_eligible") | Out-Null }

$selected = if ($blockers.Count -eq 0) { $safeCandidates[0] } else { $null }
$pilotTaskForTerminal = if ($directPilotTask) { $directPilotTask } elseif (@($pilotCandidates).Count -eq 1) { @($pilotCandidates)[0] } else { $null }
$terminalNoop = Get-PilotTerminalNoop -Task $pilotTaskForTerminal
$holdReasonFromBlockers = if (@($blockers) -contains "no_safe_pilot_task" -and @($pilotTaskLookup.rejection_reasons) -contains "duplicate_claim_rejected") {
  "duplicate_claim_rejected"
} elseif (@($pilotTaskLookup.rejection_reasons) -contains "active_lease_present") {
  "active_lease_present"
} elseif (@($pilotTaskLookup.rejection_reasons) -contains "claim_expired") {
  "claim_expired"
} elseif (@($blockers) -contains "multiple_candidates_selected") {
  "duplicate_pilot_candidates"
} elseif (@($blockers).Count -gt 0) {
  (@($blockers)[0])
} else {
  ""
}

if ($null -ne $terminalNoop) {
  $report = New-Report -Ok $true -Status $terminalNoop.status -SelectedTask $null `
    -ClaimResult ([pscustomobject]@{ would_claim = $false; claimed = $false; reason = $terminalNoop.hold_reason; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ would_run_codex = $false; codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ would_write_evidence = $false; evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus $terminalNoop.final_task_status `
    -PilotTaskLookup $pilotTaskLookup `
    -OldResidueExclusion $oldResidue `
    -TerminalState $terminalNoop.terminal_state `
    -HoldReason $terminalNoop.hold_reason `
    -FailureCategory $terminalNoop.failure_category `
    -ManualOperatorReviewNeeded $terminalNoop.manual_operator_review_needed `
    -Blockers @()
} elseif ($Mode -eq "preview") {
  $status = if ($selected) { "candidate_previewed" } else { "no_safe_candidate" }
  $report = New-Report -Ok $true -Status $status -SelectedTask $selected `
    -ClaimResult ([pscustomobject]@{ would_claim = $false; claimed = $false; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ would_run_codex = $false; codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ would_write_evidence = $false; evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus $(if ($selected) { "queued" } else { "not_selected" }) `
    -PilotTaskLookup $pilotTaskLookup `
    -OldResidueExclusion $oldResidue `
    -TerminalState $(if ($selected) { "candidate_previewed" } elseif ($holdReasonFromBlockers -in @("duplicate_claim_rejected", "active_lease_present", "claim_expired")) { "held_after_anomaly" } else { "not_selected" }) `
    -HoldReason $holdReasonFromBlockers `
    -FailureCategory $(if ($holdReasonFromBlockers -in @("duplicate_claim_rejected", "active_lease_present", "claim_expired")) { $holdReasonFromBlockers } else { "" }) `
    -ManualOperatorReviewNeeded ($holdReasonFromBlockers -in @("active_lease_present", "claim_expired")) `
    -Blockers @($blockers.ToArray())
} elseif ($Confirm -ne $ConfirmText) {
  $report = New-Report -Ok $false -Status "failed_closed" -SelectedTask $selected `
    -ClaimResult ([pscustomobject]@{ claimed = $false; reason = "confirmation_required"; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus "not_claimed" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -TerminalState "held_after_anomaly" -HoldReason "confirmation_required" -FailureCategory "confirmation_required" -Blockers @("confirmation_required")
} elseif ($null -eq $selected) {
  $report = New-Report -Ok $false -Status "failed_closed" -SelectedTask $null `
    -ClaimResult ([pscustomobject]@{ claimed = $false; reason = "candidate_mismatch"; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus "not_claimed" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -TerminalState $(if ($holdReasonFromBlockers -in @("duplicate_claim_rejected", "active_lease_present", "claim_expired")) { "held_after_anomaly" } else { "not_selected" }) -HoldReason $holdReasonFromBlockers -FailureCategory $(if ($holdReasonFromBlockers -in @("duplicate_claim_rejected", "active_lease_present", "claim_expired")) { $holdReasonFromBlockers } else { "" }) -ManualOperatorReviewNeeded ($holdReasonFromBlockers -in @("active_lease_present", "claim_expired")) -Blockers @($blockers.ToArray())
} else {
  $claimResult = [pscustomobject]@{ ok = $false; claimed = $false; task_id = $PilotTaskId; worker_id = $WorkerId; token_printed = $false }
  $finalStatus = "failed"
  try {
    if ($FixtureWorkerHeartbeatExpiredBeforeClaim) {
      $report = New-Report -Ok $false -Status "failed_closed" -SelectedTask $selected -ClaimResult ([pscustomobject]@{ ok = $false; claimed = $false; reason = "worker_heartbeat_expired_before_claim"; token_printed = $false }) `
        -ExecutionResult ([pscustomobject]@{ ok = $false; codex_run_called = $false; codex_execution_count = 0; summary = "Worker heartbeat expired before claim."; token_printed = $false }) `
        -EvidenceResult ([pscustomobject]@{ evidence_written = $false; token_printed = $false }) `
        -FinalTaskStatus "not_claimed" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -TerminalState "held_after_anomaly" -HoldReason "worker_heartbeat_expired_before_claim" -FailureCategory "worker_heartbeat_expired_before_claim" -ManualOperatorReviewNeeded $true -Blockers @("worker_heartbeat_expired_before_claim")
      throw [System.Management.Automation.StopUpstreamCommandsException]::new("")
    }
    if ($FixtureStateDir) {
      $claimResult = [pscustomobject]@{ ok = $true; claimed = $true; task_id = $PilotTaskId; worker_id = $WorkerId; claim_count = 1; heartbeat_refreshed_before_claim = $true; token_printed = $false }
    } else {
      if ([string]::IsNullOrWhiteSpace($ApiBase)) { throw "ApiBase is required for live apply." }
      $config = [pscustomobject]@{ api_base = $ApiBase; auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile; worker_id = $WorkerId }
      Send-WorkerHeartbeat -Config $config -StatusNote "start_one_apply_pilot_claim_guard" -Load 0 -TimeoutSeconds $TimeoutSeconds | Out-Null
      $claim = Claim-Task -Config $config -TaskId $PilotTaskId -TimeoutSeconds $TimeoutSeconds
      $claimResult = [pscustomobject]@{ ok = $true; claimed = $true; task_id = $PilotTaskId; worker_id = $WorkerId; claim_status = [string](Get-Prop -Object (Get-Prop -Object $claim -Name "task") -Name "status" -Default "claimed"); claim_count = 1; heartbeat_refreshed_before_claim = $true; token_printed = $false }
      Start-Task -Config $config -TaskId $PilotTaskId -TimeoutSeconds $TimeoutSeconds | Out-Null
    }
    if ($FixtureWorkerHeartbeatExpiredAfterClaim) {
      $execution = [pscustomobject]@{ ok = $false; failure_category = "worker_heartbeat_expired_after_claim"; terminal_state = "held_after_anomaly"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); summary = "Worker heartbeat expired after claim; stopped before Codex."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
    } elseif ($FixtureTaskStatusMismatchAfterClaim) {
      $execution = [pscustomobject]@{ ok = $false; failure_category = "task_status_mismatch_after_claim"; terminal_state = "held_after_anomaly"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); summary = "Task status mismatch after claim; stopped before Codex."; validation_commands = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
    } else {
      $execution = Invoke-PilotCodexOnce
    }
    $finalStatus = if ($execution.ok) { "completed" } else { "failed_with_evidence" }
    $terminalState = if ($execution.ok) { "completed_with_evidence" } else { [string](Get-Prop -Object $execution -Name "terminal_state" -Default "failed_with_evidence") }
    $failureCategory = [string](Get-Prop -Object $execution -Name "failure_category" -Default "")
    $evidence = Write-Evidence -Status $finalStatus -TerminalState $terminalState -FailureCategory $failureCategory -FilesChanged @($execution.files_changed) -AllowedPaths @($AllowedPath) -ValidationCommands @($execution.validation_commands) -ValidationResult (Get-Prop -Object $execution -Name "validation_result") -Summary ([string]$execution.summary) -NoOldResidueSelected $true -ClaimResult $claimResult
    if (-not [bool]$evidence.ok) {
      $finalStatus = "failed_with_evidence"
      $terminalState = "evidence_write_failed"
      $failureCategory = "evidence_write_failed"
    }
    if (-not $FixtureStateDir) {
      $config = [pscustomobject]@{ api_base = $ApiBase; auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile; worker_id = $WorkerId }
      $body = @{ summary = [string]$execution.summary; evidence_summary = $evidence.evidence }
      if ($execution.ok) {
        $completeResponse = Complete-Task -Config $config -TaskId $PilotTaskId -Result $body -TimeoutSeconds $TimeoutSeconds
        if ($null -eq (Get-Prop -Object $completeResponse -Name "task" -Default $completeResponse)) { $failureCategory = "complete_api_unexpected_response"; $terminalState = "held_after_anomaly"; $finalStatus = "failed_with_evidence" }
      } else {
        $failResponse = Fail-Task -Config $config -TaskId $PilotTaskId -Result $body -TimeoutSeconds $TimeoutSeconds
        if ($null -eq (Get-Prop -Object $failResponse -Name "task" -Default $failResponse)) { $failureCategory = "fail_api_unexpected_response"; $terminalState = "held_after_anomaly" }
      }
    } elseif ($FixtureCompleteApiUnexpectedResponse -and $execution.ok) {
      $failureCategory = "complete_api_unexpected_response"; $terminalState = "held_after_anomaly"; $finalStatus = "failed_with_evidence"
    } elseif ($FixtureFailApiUnexpectedResponse -and -not $execution.ok) {
      $failureCategory = "fail_api_unexpected_response"; $terminalState = "held_after_anomaly"
    }
    $report = New-Report -Ok ([bool]($execution.ok -and $finalStatus -eq "completed")) -Status $finalStatus -SelectedTask $selected -ClaimResult $claimResult -ExecutionResult $execution -EvidenceResult $evidence -FinalTaskStatus $finalStatus -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -TerminalState $terminalState -HoldReason $(if ($failureCategory) { $failureCategory } else { "" }) -FailureCategory $failureCategory -ManualOperatorReviewNeeded (-not [bool]$execution.ok -or $terminalState -eq "held_after_anomaly" -or $terminalState -eq "evidence_write_failed") -Blockers @()
  } catch {
    if ($null -eq $report) {
      $safeError = ConvertTo-SafeText -Text $_.Exception.Message
      $evidence = Write-Evidence -Status "failed_with_evidence" -TerminalState "held_after_anomaly" -FailureCategory "apply_failed_closed" -FilesChanged @() -ValidationCommands @() -ValidationResult ([pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }) -Summary "Pilot failed closed: $safeError" -NoOldResidueSelected $true -ClaimResult $claimResult
      $report = New-Report -Ok $false -Status "failed_with_evidence" -SelectedTask $selected -ClaimResult $claimResult `
        -ExecutionResult ([pscustomobject]@{ ok = $false; codex_run_called = $false; codex_execution_count = 0; summary = "Pilot failed closed."; token_printed = $false }) `
        -EvidenceResult $evidence -FinalTaskStatus "failed_with_evidence" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -TerminalState "held_after_anomaly" -HoldReason "apply_failed_closed" -FailureCategory "apply_failed_closed" -ManualOperatorReviewNeeded $true -Blockers @("apply_failed_closed")
    }
  }
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "Status:       $($report.status)"
  "Selected:     $(if ($report.selected_task_id) { $report.selected_task_id } else { 'none' })"
  "Claimed:      $($report.claim_result.claimed)"
  "CodexRuns:    $($report.execution_result.codex_execution_count)"
  "FinalStatus:  $($report.final_task_status)"
  "TokenPrinted: false"
}
