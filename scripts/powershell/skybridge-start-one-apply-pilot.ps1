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
  [switch]$FixtureCodexFailure
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
    [string[]]$FilesChanged,
    [string[]]$ValidationCommands,
    [string]$Summary,
    [bool]$NoOldResidueSelected
  )
  New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
  $evidence = [pscustomobject]@{
    schema = "skybridge.start_one_apply_pilot_evidence.v1"
    task_id = $PilotTaskId
    selected_worker_id = $WorkerId
    status = $Status
    files_changed = @($FilesChanged)
    validation_commands = @($ValidationCommands)
    execution_summary = $Summary
    safety = [pscustomobject]@{
      no_old_residue_selected = $NoOldResidueSelected
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
  [pscustomobject]@{ ok = $true; evidence_path = $EvidencePath; evidence = $evidence; token_printed = $false }
}

function Invoke-PilotCodexOnce {
  if ($FixtureCodexFailure) {
    return [pscustomobject]@{ ok = $false; codex_run_called = $true; codex_execution_count = 1; files_changed = @(); summary = "Fixture Codex execution failed safely."; validation_commands = @(); token_printed = $false }
  }
  if ($FixtureCodexSuccess) {
    return [pscustomobject]@{ ok = $true; codex_run_called = $true; codex_execution_count = 1; files_changed = @($AllowedPath); summary = "Fixture Codex execution updated the pilot docs evidence path."; validation_commands = @("fixture-validation"); token_printed = $false }
  }
  $codex = Get-Command codex -ErrorAction SilentlyContinue
  if ($null -eq $codex) {
    return [pscustomobject]@{ ok = $false; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); summary = "Codex CLI unavailable; failed closed after the single pilot claim."; validation_commands = @(); token_printed = $false }
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
    return [pscustomobject]@{ ok = $false; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); summary = "Codex execution failed or changed an unexpected path."; validation_commands = @(); token_printed = $false }
  }
  [pscustomobject]@{ ok = $true; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); summary = "Codex execution completed the docs-only pilot update."; validation_commands = @("git diff --name-only"); token_printed = $false }
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
    [string[]]$Blockers = @()
  )
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
      would_claim = ($Mode -eq "apply" -and $Ok)
      would_run_codex = ($Mode -eq "apply" -and $Ok)
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

if ($Mode -eq "preview") {
  $status = if ($selected) { "candidate_previewed" } else { "no_safe_candidate" }
  $report = New-Report -Ok $true -Status $status -SelectedTask $selected `
    -ClaimResult ([pscustomobject]@{ would_claim = $false; claimed = $false; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ would_run_codex = $false; codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ would_write_evidence = $false; evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus $(if ($selected) { "queued" } else { "not_selected" }) `
    -PilotTaskLookup $pilotTaskLookup `
    -OldResidueExclusion $oldResidue `
    -Blockers @($blockers.ToArray())
} elseif ($Confirm -ne $ConfirmText) {
  $report = New-Report -Ok $false -Status "failed_closed" -SelectedTask $selected `
    -ClaimResult ([pscustomobject]@{ claimed = $false; reason = "confirmation_required"; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus "not_claimed" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -Blockers @("confirmation_required")
} elseif ($null -eq $selected) {
  $report = New-Report -Ok $false -Status "failed_closed" -SelectedTask $null `
    -ClaimResult ([pscustomobject]@{ claimed = $false; reason = "candidate_mismatch"; token_printed = $false }) `
    -ExecutionResult ([pscustomobject]@{ codex_run_called = $false; codex_execution_count = 0; token_printed = $false }) `
    -EvidenceResult ([pscustomobject]@{ evidence_written = $false; token_printed = $false }) `
    -FinalTaskStatus "not_claimed" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -Blockers @($blockers.ToArray())
} else {
  $claimResult = [pscustomobject]@{ ok = $false; claimed = $false; task_id = $PilotTaskId; worker_id = $WorkerId; token_printed = $false }
  $finalStatus = "failed"
  try {
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
    $execution = Invoke-PilotCodexOnce
    $finalStatus = if ($execution.ok) { "completed" } else { "failed_with_evidence" }
    $evidence = Write-Evidence -Status $finalStatus -FilesChanged @($execution.files_changed) -ValidationCommands @($execution.validation_commands) -Summary ([string]$execution.summary) -NoOldResidueSelected $true
    if (-not $FixtureStateDir) {
      $config = [pscustomobject]@{ api_base = $ApiBase; auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile; worker_id = $WorkerId }
      $body = @{ summary = [string]$execution.summary; evidence_summary = $evidence.evidence }
      if ($execution.ok) { Complete-Task -Config $config -TaskId $PilotTaskId -Result $body -TimeoutSeconds $TimeoutSeconds | Out-Null } else { Fail-Task -Config $config -TaskId $PilotTaskId -Result $body -TimeoutSeconds $TimeoutSeconds | Out-Null }
    }
    $report = New-Report -Ok ([bool]$execution.ok) -Status $finalStatus -SelectedTask $selected -ClaimResult $claimResult -ExecutionResult $execution -EvidenceResult $evidence -FinalTaskStatus $finalStatus -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -Blockers @()
  } catch {
    $safeError = ConvertTo-SafeText -Text $_.Exception.Message
    $evidence = Write-Evidence -Status "failed_with_evidence" -FilesChanged @() -ValidationCommands @() -Summary "Pilot failed closed: $safeError" -NoOldResidueSelected $true
    $report = New-Report -Ok $false -Status "failed_with_evidence" -SelectedTask $selected -ClaimResult $claimResult `
      -ExecutionResult ([pscustomobject]@{ ok = $false; codex_run_called = $false; codex_execution_count = 0; summary = "Pilot failed closed."; token_printed = $false }) `
      -EvidenceResult $evidence -FinalTaskStatus "failed_with_evidence" -OldResidueExclusion $oldResidue -PilotTaskLookup $pilotTaskLookup -Blockers @("apply_failed_closed")
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
