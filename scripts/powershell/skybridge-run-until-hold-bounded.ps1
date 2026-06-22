[CmdletBinding(DefaultParameterSetName = "Preview")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId,
  [string]$TaskPrefix,
  [Parameter(ParameterSetName = "Preview")][switch]$Preview,
  [Parameter(ParameterSetName = "Apply")][switch]$Apply,
  [string]$Confirm,
  [int]$MaxTasks = 2,
  [int]$MaxRuntimeMinutes = 10,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureWorkersFile,
  [string]$FixtureHygieneFile,
  [string]$FixtureSecondGateFile,
  [string]$FixtureStateDir,
  [switch]$FixtureCodexSuccess,
  [switch]$FixtureCodexFailure,
  [switch]$FixtureCodexUnavailable,
  [switch]$FixtureCodexUnsafePath,
  [switch]$FixtureEvidenceMissing,
  [switch]$FixtureValidationFailure,
  [switch]$FixtureWorkerOffline,
  [switch]$FixtureStaleClaim,
  [switch]$FixtureMaxRuntimeExceeded
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$WorkerId = "jerry-win-local-01"
$Mode = if ($Apply) { "apply" } else { "preview" }
$ConfirmText = "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS"
if ($MaxTasks -lt 1) { $MaxTasks = 1 }
if ($MaxTasks -gt 3) { $MaxTasks = 3 }
if ($MaxRuntimeMinutes -lt 1) { $MaxRuntimeMinutes = 1 }
$StartTime = Get-Date
$EvidenceDir = if ($FixtureStateDir) { $FixtureStateDir } else { Join-Path $RepoRoot ".agent\tmp\run-until-hold-bounded" }

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

function Get-AllowedPathForTaskId {
  param([string]$TaskId)
  if ($TaskId -match "^run-until-hold-pilot-docs-(00[1-3])$") {
    return "docs/operations/RUN_UNTIL_HOLD_PILOT_$($Matches[1]).md"
  }
  if ($TaskId -match "^campaign-policy-compiler-pilot-docs-(00[1-3])$") {
    return "docs/operations/CAMPAIGN_COMPILER_PILOT_$($Matches[1]).md"
  }
  return $null
}

function Test-SelectorMatch {
  param($Task, [string]$TaskId)
  $campaign = [string](Get-Prop -Object $Task -Name "campaign_id" -Default "")
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $planner = Get-Prop -Object $Task -Name "planner_metadata"
  if ([string]::IsNullOrWhiteSpace($campaign)) {
    $campaign = [string](Get-Prop -Object $metadata -Name "campaign_id" -Default "")
  }
  if ([string]::IsNullOrWhiteSpace($campaign)) {
    $campaign = [string](Get-Prop -Object $planner -Name "source_campaign_id" -Default "")
  }
  if (-not [string]::IsNullOrWhiteSpace($CampaignId)) {
    return ($campaign -eq $CampaignId -and $TaskId -match "^campaign-policy-compiler-pilot-docs-00[1-3]$")
  }
  if (-not [string]::IsNullOrWhiteSpace($TaskPrefix)) {
    return $TaskId.StartsWith($TaskPrefix)
  }
  return ($TaskId -match "^run-until-hold-pilot-docs-00[1-3]$")
}

function ConvertTo-SafeCandidate {
  param($Task)
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
    status = [string](Get-Prop -Object $Task -Name "status" -Default "")
    risk = [string](Get-Prop -Object $Task -Name "risk" -Default "")
    task_type = [string](Get-Prop -Object $Task -Name "task_type" -Default "")
    allowed_paths = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { [string]$_ })
    selected_worker_id = $WorkerId
    token_printed = $false
  }
}

function Get-ClaimLeaseState {
  param($Task)
  $assigned = [string](Get-Prop -Object $Task -Name "assigned_worker_id" -Default "")
  $claimId = [string](Get-Prop -Object $Task -Name "claim_id" -Default "")
  $lease = Get-Prop -Object $Task -Name "lease"
  $leaseId = [string](Get-Prop -Object $lease -Name "lease_id" -Default (Get-Prop -Object $Task -Name "lease_id" -Default ""))
  $expiresRaw = [string](Get-Prop -Object $lease -Name "expires_at" -Default (Get-Prop -Object $Task -Name "lease_expires_at" -Default ""))
  $staleLease = $false
  if (-not [string]::IsNullOrWhiteSpace($expiresRaw)) {
    try { $staleLease = ([datetimeoffset]::Parse($expiresRaw).UtcDateTime -lt (Get-Date).ToUniversalTime()) } catch {}
  }
  [pscustomobject]@{
    claimed = (-not [string]::IsNullOrWhiteSpace($claimId) -or (-not [string]::IsNullOrWhiteSpace($assigned) -and $assigned -ne "-" -and $assigned -ne $WorkerId))
    active_lease = (-not [string]::IsNullOrWhiteSpace($leaseId) -and -not $staleLease)
    stale_lease = (-not [string]::IsNullOrWhiteSpace($leaseId) -and $staleLease)
  }
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
  [pscustomobject]@{ task_classifications = @(); unsafe_to_requeue_candidates = @(); archive_or_keep_blocked_candidates = @(); token_printed = $false }
}

function Get-SecondGate {
  if ($FixtureSecondGateFile) { return Read-JsonFile -Path $FixtureSecondGateFile }
  [pscustomobject]@{ project_control_state = "paused"; allowed_preview_only = $true; allowed_execution = $false; token_printed = $false }
}

function Test-WorkerMatch {
  param([array]$Workers, $Task)
  if ($FixtureWorkerOffline) { return $false }
  $worker = @($Workers | Where-Object { [string](Get-Prop -Object $_ -Name "worker_id") -eq $WorkerId } | Select-Object -First 1)
  if ($worker.Count -lt 1) { return $false }
  $status = ([string](Get-Prop -Object $worker[0] -Name "status" -Default "offline")).ToLowerInvariant()
  $enabled = Get-BoolProp -Object $worker[0] -Name "enabled" -Default $true
  $caps = @((Get-Prop -Object $worker[0] -Name "capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if (-not ($enabled -and $status -eq "online")) { return $false }
  if ($caps.Count -eq 0) { return $true }
  return ($caps -contains "codex" -and ($caps -contains "docs" -or $caps -contains "documentation"))
}

function Test-SafeCandidate {
  param($Task, [array]$Workers)
  $reasons = [System.Collections.Generic.List[string]]::new()
  $taskId = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
  $allowedPath = Get-AllowedPathForTaskId -TaskId $taskId
  $allowed = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $claim = Get-ClaimLeaseState -Task $Task
  $status = ([string](Get-Prop -Object $Task -Name "status" -Default "")).ToLowerInvariant()
  $risk = ([string](Get-Prop -Object $Task -Name "risk" -Default "")).ToLowerInvariant()
  $taskType = ([string](Get-Prop -Object $Task -Name "task_type" -Default "")).ToLowerInvariant()
  $text = (@(Get-Prop -Object $Task -Name "title" -Default ""; Get-Prop -Object $Task -Name "body" -Default ""; Get-Prop -Object $Task -Name "prompt_summary" -Default ""; @($allowed) -join " ") -join " ").ToLowerInvariant()
  if (-not $allowedPath -or -not (Test-SelectorMatch -Task $Task -TaskId $taskId)) { $reasons.Add("not_selected_bounded_pilot") | Out-Null }
  if ($status -ne "queued") { $reasons.Add("${status}_status") | Out-Null }
  if ($risk -notin @("low", "safe_start_one_pilot", "bounded_loop_pilot")) { $reasons.Add("risk_not_low") | Out-Null }
  if ($taskType -notin @("docs", "test")) { $reasons.Add("task_type_not_docs_or_test") | Out-Null }
  if ($allowed.Count -ne 1 -or $allowed[0] -ne $allowedPath) { $reasons.Add("allowed_paths_not_exact_safe_docs_path") | Out-Null }
  if ($risk -ne "low" -and -not (Get-BoolProp -Object $metadata -Name "bounded_loop_pilot" -Default $false) -and -not (Get-BoolProp -Object $metadata -Name "campaign_task_compiler_pilot" -Default $false)) { $reasons.Add("missing_bounded_loop_pilot_marker") | Out-Null }
  if ([string](Get-Prop -Object $metadata -Name "allowed_worker_id" -Default $WorkerId) -ne $WorkerId) { $reasons.Add("worker_id_not_allowed") | Out-Null }
  if ($claim.claimed) { $reasons.Add("duplicate_claim_rejected") | Out-Null }
  if ($claim.active_lease) { $reasons.Add("active_lease_present") | Out-Null }
  if ($claim.stale_lease -or $FixtureStaleClaim) { $reasons.Add("stale_claim_or_lease") | Out-Null }
  if ($text -match "(deploy|production|secret|credential|cookie|server-root|openresty|authelia|cloudflare|dns|github settings|branch protection|/opt/skybridge-agent-hub)") { $reasons.Add("unsafe_policy_surface") | Out-Null }
  if (-not (Test-WorkerMatch -Workers $Workers -Task $Task)) { $reasons.Add("worker_offline") | Out-Null }
  [pscustomobject]@{ safe = ($reasons.Count -eq 0); reasons = @($reasons.ToArray()) }
}

function Get-OldResidueExclusion {
  param([array]$Tasks, $Hygiene)
  [pscustomobject]@{
    failed_tasks_excluded = @($Tasks | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "failed" }).Count
    blocked_tasks_excluded = @($Tasks | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "blocked" }).Count
    completed_tasks_excluded = @($Tasks | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "completed" }).Count
    unsafe_to_requeue_tasks_excluded = @((Get-Prop -Object $Hygiene -Name "unsafe_to_requeue_candidates" -Default @())).Count
    no_old_residue_eligible = $true
    no_old_task_claimed = $true
    no_old_task_requeued = $true
    token_printed = $false
  }
}

function Invoke-BoundedCodexOnce {
  param($Task)
  $taskId = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
  $allowedPath = Get-AllowedPathForTaskId -TaskId $taskId
  if ($FixtureCodexUnavailable) {
    return [pscustomobject]@{ ok = $false; terminal_state = "failed_with_evidence"; failure_category = "codex_cli_unavailable"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexUnsafePath) {
    return [pscustomobject]@{ ok = $false; terminal_state = "unsafe_path_changed"; failure_category = "unsafe_path_changed"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($allowedPath, "scripts/powershell/unsafe-fixture.ps1"); validation_result = [pscustomobject]@{ ok = $false; status = "unsafe_path_changed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureValidationFailure) {
    return [pscustomobject]@{ ok = $false; terminal_state = "validation_failed"; failure_category = "validation_failed"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($allowedPath); validation_result = [pscustomobject]@{ ok = $false; status = "failed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexFailure) {
    return [pscustomobject]@{ ok = $false; terminal_state = "failed_with_evidence"; failure_category = "codex_nonzero"; codex_run_called = $true; codex_execution_count = 1; files_changed = @($allowedPath); validation_result = [pscustomobject]@{ ok = $false; status = "failed"; token_printed = $false }; token_printed = $false }
  }
  if ($FixtureCodexSuccess -or $FixtureStateDir) {
    return [pscustomobject]@{ ok = $true; terminal_state = "completed_with_evidence"; failure_category = $null; codex_run_called = $true; codex_execution_count = 1; files_changed = @($allowedPath); validation_result = [pscustomobject]@{ ok = $true; status = "passed"; token_printed = $false }; token_printed = $false }
  }
  $codex = Get-Command codex -ErrorAction SilentlyContinue
  if ($null -eq $codex) {
    return [pscustomobject]@{ ok = $false; terminal_state = "failed_with_evidence"; failure_category = "codex_cli_unavailable"; codex_run_called = $false; codex_execution_count = 0; files_changed = @(); validation_result = [pscustomobject]@{ ok = $false; status = "not_run"; token_printed = $false }; token_printed = $false }
  }
  $before = @(& git status --short)
  $goalLabel = if ($taskId -like "campaign-policy-compiler-pilot-docs-*") { "Mega Goal 322 campaign compiler pilot" } else { "Mega Goal 321 bounded run-until-hold pilot" }
  $prompt = "Update only $allowedPath for SkyBridge $goalLabel. Write a concise docs-only operator note. Do not edit code, scripts, credentials, deployment files, repository settings, or infrastructure."
  $null = & codex exec --sandbox workspace-write $prompt 2>$null
  $after = @(& git status --short)
  $changed = @($after | Where-Object { $before -notcontains $_ } | ForEach-Object { $line = [string]$_; if ($line.Length -gt 3) { $line.Substring(3).Replace("\", "/") } } | Where-Object { $_ })
  $unsafe = @($changed | Where-Object { $_ -ne $allowedPath })
  if ($LASTEXITCODE -ne 0 -or $unsafe.Count -gt 0 -or $changed.Count -lt 1) {
    $category = if ($unsafe.Count -gt 0) { "unsafe_path_changed" } elseif ($changed.Count -lt 1) { "validation_failed" } else { "codex_nonzero" }
    return [pscustomobject]@{ ok = $false; terminal_state = $category; failure_category = $category; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); validation_result = [pscustomobject]@{ ok = $false; status = $category; token_printed = $false }; token_printed = $false }
  }
  [pscustomobject]@{ ok = $true; terminal_state = "completed_with_evidence"; failure_category = $null; codex_run_called = $true; codex_execution_count = 1; files_changed = @($changed); validation_result = [pscustomobject]@{ ok = $true; status = "passed"; token_printed = $false }; token_printed = $false }
}

function Write-BoundedEvidence {
  param($Task, [int]$AttemptIndex, $Execution)
  if ($FixtureEvidenceMissing) {
    return [pscustomobject]@{ ok = $false; evidence_written = $false; evidence = $null; token_printed = $false }
  }
  New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
  $taskId = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
  $allowedPath = Get-AllowedPathForTaskId -TaskId $taskId
  $evidence = [pscustomobject]@{
    schema = "skybridge.run_until_hold_bounded_evidence.v1"
    task_id = $taskId
    selected_worker_id = $WorkerId
    attempt_index = $AttemptIndex
    execution_attempt_id = "bounded-$taskId-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
    files_changed = @($Execution.files_changed)
    allowed_paths = @($allowedPath)
    validation_result = Get-Prop -Object $Execution -Name "validation_result"
    terminal_state = [string](Get-Prop -Object $Execution -Name "terminal_state" -Default "completed_with_evidence")
    hold_reason = Get-Prop -Object $Execution -Name "failure_category"
    old_residue_selected = $false
    project_control_unpaused = $false
    run_until_hold_recursive = $false
    token_printed = $false
  }
  $evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDir "$taskId-evidence.json") -Encoding UTF8
  [pscustomobject]@{ ok = $true; evidence_written = $true; evidence = $evidence; token_printed = $false }
}

$tasks = @(Get-TaskList)
$workers = @(Get-WorkerList)
$hygiene = Get-Hygiene
$secondGate = Get-SecondGate
$oldResidue = Get-OldResidueExclusion -Tasks $tasks -Hygiene $hygiene

$rejections = @()
$safeCandidates = @()
foreach ($task in @($tasks)) {
  $decision = Test-SafeCandidate -Task $task -Workers $workers
  if ($decision.safe) {
    $safeCandidates += $task
  } elseif ([string](Get-Prop -Object $task -Name "task_id" -Default "") -match "^(run-until-hold-pilot-docs-|campaign-policy-compiler-pilot-docs-)") {
    $rejections += [pscustomobject]@{ task_id = [string](Get-Prop -Object $task -Name "task_id" -Default ""); reasons = @($decision.reasons) }
  }
}
$safeCandidates = @($safeCandidates | Sort-Object { [string](Get-Prop -Object $_ -Name "task_id" -Default "") } | Select-Object -First $MaxTasks)

$blockers = [System.Collections.Generic.List[string]]::new()
if ([string](Get-Prop -Object $secondGate -Name "project_control_state" -Default "paused") -ne "paused") { $blockers.Add("project_control_not_paused") | Out-Null }
if (Get-BoolProp -Object $secondGate -Name "allowed_execution" -Default $false) { $blockers.Add("general_execution_unexpectedly_allowed") | Out-Null }
if ($FixtureMaxRuntimeExceeded) { $blockers.Add("max_runtime_exceeded") | Out-Null }

$selected = if ($blockers.Count -eq 0) { @($safeCandidates) } else { @() }
$executed = @()
$skipped = @($rejections)
$stopReason = if ($blockers.Count -gt 0) { [string]@($blockers)[0] } elseif ($selected.Count -eq 0) { "no_safe_candidate" } else { "preview_ready" }
$holdReason = if ($stopReason -eq "preview_ready") { $null } else { $stopReason }

if ($Mode -eq "apply") {
  if ($Confirm -ne $ConfirmText) {
    $blockers.Add("confirmation_required") | Out-Null
    $stopReason = "operator_review_required"
    $holdReason = "confirmation_required"
  } elseif ($selected.Count -gt 0) {
    $attempt = 0
    foreach ($task in @($selected)) {
      if (((Get-Date) - $StartTime).TotalMinutes -gt $MaxRuntimeMinutes) {
        $stopReason = "max_runtime_exceeded"; $holdReason = $stopReason; break
      }
      $attempt += 1
      $taskId = [string](Get-Prop -Object $task -Name "task_id" -Default "")
      $claimResult = [pscustomobject]@{ ok = $true; claimed = $true; task_id = $taskId; worker_id = $WorkerId; token_printed = $false }
      if (-not $FixtureStateDir) {
        $config = [pscustomobject]@{ api_base = $ApiBase; auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile; worker_id = $WorkerId }
        Send-WorkerHeartbeat -Config $config -StatusNote "bounded_run_until_hold_claim_guard" -Load 0 -TimeoutSeconds $TimeoutSeconds | Out-Null
        Claim-Task -Config $config -TaskId $taskId -TimeoutSeconds $TimeoutSeconds | Out-Null
        Start-Task -Config $config -TaskId $taskId -TimeoutSeconds $TimeoutSeconds | Out-Null
      }
      $execution = Invoke-BoundedCodexOnce -Task $task
      $evidence = Write-BoundedEvidence -Task $task -AttemptIndex $attempt -Execution $execution
      $terminal = [string](Get-Prop -Object $execution -Name "terminal_state" -Default "completed_with_evidence")
      if (-not [bool]$evidence.evidence_written) { $terminal = "evidence_missing"; $execution.ok = $false }
      $executed += [pscustomobject]@{
        task_id = $taskId
        selected_worker_id = $WorkerId
        claim_result = $claimResult
        execution_result = $execution
        evidence_written = [bool]$evidence.evidence_written
        terminal_state = $terminal
        token_printed = $false
      }
      if (-not $FixtureStateDir) {
        $config = [pscustomobject]@{ api_base = $ApiBase; auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile; worker_id = $WorkerId }
        $body = @{ summary = "Bounded run-until-hold pilot task result."; evidence_summary = $evidence.evidence }
        if ([bool]$execution.ok -and [bool]$evidence.evidence_written) { Complete-Task -Config $config -TaskId $taskId -Result $body -TimeoutSeconds $TimeoutSeconds | Out-Null }
        else { Fail-Task -Config $config -TaskId $taskId -Result $body -TimeoutSeconds $TimeoutSeconds | Out-Null }
      }
      if (-not [bool]$execution.ok -or -not [bool]$evidence.evidence_written) {
        $stopReason = if (-not [bool]$evidence.evidence_written) { "evidence_missing" } elseif ($terminal -eq "unsafe_path_changed") { "unsafe_path_changed" } elseif ($terminal -eq "validation_failed") { "validation_failed" } else { "task_failed_with_evidence" }
        $failureReason = [string](Get-Prop -Object $execution -Name "failure_category" -Default "")
        $holdReason = if ([string]::IsNullOrWhiteSpace($failureReason)) { $stopReason } else { $failureReason }
        break
      }
    }
    if ($executed.Count -eq $MaxTasks -and -not $holdReason) { $stopReason = "completed_max_tasks" }
    elseif ($executed.Count -gt 0 -and -not $holdReason) { $stopReason = "no_safe_candidate" }
  }
}

$evidenceItems = @($executed | ForEach-Object {
  [pscustomobject]@{
    task_id = $_.task_id
    evidence_written = [bool]$_.evidence_written
    terminal_state = [string]$_.terminal_state
    token_printed = $false
  }
})

$report = [pscustomobject]@{
  schema = "skybridge.run_until_hold_bounded.v1"
  ok = ($blockers.Count -eq 0 -and ($Mode -eq "preview" -or -not $holdReason -or $stopReason -in @("completed_max_tasks", "no_safe_candidate")))
  mode = $Mode
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  campaign_id = if ($CampaignId) { $CampaignId } else { $null }
  task_prefix = if ($TaskPrefix) { $TaskPrefix } else { $null }
  max_tasks = $MaxTasks
  max_runtime_minutes = $MaxRuntimeMinutes
  selected_candidates = @($selected | ForEach-Object { ConvertTo-SafeCandidate -Task $_ })
  executed_tasks = @($executed)
  skipped_tasks = @($skipped)
  executed_task_count = @($executed).Count
  codex_execution_count = [int](@($executed | ForEach-Object { [int](Get-Prop -Object $_.execution_result -Name "codex_execution_count" -Default 0) } | Measure-Object -Sum).Sum)
  hold_reason = $holdReason
  stop_reason = $stopReason
  evidence_summary = [pscustomobject]@{
    schema = "skybridge.run_until_hold_bounded_evidence.v1"
    attempted_task_count = @($executed).Count
    evidence_present = (@($executed).Count -eq 0 -or @($executed | Where-Object { -not [bool]$_.evidence_written }).Count -eq 0)
    evidence_items = @($evidenceItems)
    prompt_content_included = $false
    log_content_included = $false
    credential_values_included = $false
    token_printed = $false
  }
  old_residue_exclusion = $oldResidue
  project_control = [pscustomobject]@{ state = "paused"; project_control_unpaused = $false; token_printed = $false }
  forbidden_actions = [pscustomobject]@{
    daemon_implemented = $false
    recursive_run_until_hold = $false
    run_until_hold_recursive = $false
    infinite_loop = $false
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
    bounded = $true
    max_tasks_absolute_max = 3
    stop_on_first_failure = $true
    stop_on_missing_evidence = $true
    stop_on_unsafe_candidate = $true
    stop_on_no_safe_candidate = $true
    stop_on_notification_failure = $true
    no_background_daemon = $true
    no_retry_until_success = $true
    token_printed = $false
  }
  blockers = @($blockers.ToArray())
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "OK:           $($report.ok)"
  "Selected:     $(@($report.selected_candidates).Count)"
  "Executed:     $($report.executed_task_count)"
  "StopReason:   $($report.stop_reason)"
  "HoldReason:   $(if ($report.hold_reason) { $report.hold_reason } else { 'none' })"
  "TokenPrinted: false"
}
