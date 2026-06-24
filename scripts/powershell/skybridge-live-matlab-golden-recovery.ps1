param(
  [ValidateSet("status", "doctor-preview", "doctor-apply", "preview-create", "apply-create", "preview-run", "apply-run", "report", "safe-summary")]
  [string]$Command = "status",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "live-matlab-golden-task-334-001",
  [string]$TemplateId = "matlab-parameter-sweep.v1",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$RecoveryTaskId = "live-matlab-golden-task-334-001"
$DoNotReuseTaskId = "live-matlab-golden-task-333-001"
$WorkerIdTarget = "jerry-win-local-01"
$TemplateIdTarget = "matlab-parameter-sweep.v1"
$RunnerIdTarget = "matlab-parameter-sweep-runner.v1"
$EvidenceSchemaId = "skybridge.matlab_sweep_evidence.v1"
$DoctorConfirmationPhrase = "I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY"
$CreateConfirmationPhrase = "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY"
$RunConfirmationPhrase = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY"
$RunnerConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY"
$RequiredCapabilities = @("windows", "powershell", "matlab")
$AllowedPaths = @(".agent/tmp/matlab-golden-trial/**", "results/skybridge/matlab-golden-trial/**")
$BlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 24
}

function ConvertTo-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  return @($Value)
}

function Get-PropertyValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Test-ContainsAll {
  param([string[]]$Actual, [string[]]$Required)
  foreach ($item in $Required) {
    if ($Actual -notcontains $item) { return $false }
  }
  return $true
}

function Test-Subset {
  param([string[]]$Actual, [string[]]$Allowed)
  foreach ($item in $Actual) {
    if ($Allowed -notcontains $item) { return $false }
  }
  return $true
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $positiveText = $Text -replace "(?i)\bNo\s+[^.]*\.", " "
  $positiveText = $positiveText -replace "(?i)\bNot\s+[^.]*\.", " "
  [bool]($positiveText -match "(?i)\b(production|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|cookie|authorization|bearer|raw command|cmd\.exe|powershell -|pwsh -|bash -|codex|unbounded|arbitrary command)\b")
}

function Get-ConfigValueFromFile {
  param([string]$Path, [string]$Name)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  $text = Get-Content -Raw -LiteralPath $Path
  $pattern = "(?m)^\s*\`$env:$([regex]::Escape($Name))\s*=\s*['""]?([^'""\r\n]+)['""]?"
  $match = [regex]::Match($text, $pattern)
  if ($match.Success) { return $match.Groups[1].Value.Trim() }
  ""
}

function Resolve-HomePathValue {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  $Value.Replace('$HOME', $profileHome).Replace('~', $profileHome)
}

$HomeRoot = [Environment]::GetFolderPath("UserProfile")
$SkyBridgeConfigPath = Join-Path $HomeRoot ".skybridge\skybridge.env.ps1"
$WorkerConfigPath = Join-Path $HomeRoot ".skybridge\worker.env.ps1"

if ([string]::IsNullOrWhiteSpace($ApiBase)) {
  $ApiBase = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) { $env:SKYBRIDGE_API_BASE } else { Get-ConfigValueFromFile -Path $SkyBridgeConfigPath -Name "SKYBRIDGE_API_BASE" }
}
if ([string]::IsNullOrWhiteSpace($TokenFile)) {
  $TokenFile = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE)) { $env:SKYBRIDGE_WORKER_TOKEN_FILE } else { Get-ConfigValueFromFile -Path $WorkerConfigPath -Name "SKYBRIDGE_WORKER_TOKEN_FILE" }
}
if ([string]::IsNullOrWhiteSpace($TokenFile)) {
  $TokenFile = Join-Path $HomeRoot ".skybridge\worker-token.txt"
}
$TokenFile = Resolve-HomePathValue $TokenFile
if ([string]::IsNullOrWhiteSpace($WorkerId)) {
  $WorkerId = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_ID)) { $env:SKYBRIDGE_WORKER_ID } else { Get-ConfigValueFromFile -Path $WorkerConfigPath -Name "SKYBRIDGE_WORKER_ID" }
}
if ([string]::IsNullOrWhiteSpace($WorkerId)) { $WorkerId = $WorkerIdTarget }

function Get-AuthHeaders {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($TokenFile) -and (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
    $token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $headers["Authorization"] = "Bearer $token"
    }
  }
  $headers
}

function Invoke-RecoveryApi {
  param(
    [ValidateSet("GET", "POST")]
    [string]$Method,
    [string]$Path,
    $Body = $null
  )
  if ([string]::IsNullOrWhiteSpace($ApiBase)) {
    return [pscustomobject]@{ status_code = 0; body = [pscustomobject]@{ ok = $false; error = "api_base_not_configured"; token_printed = $false } }
  }
  $parameters = @{
    Method = $Method
    Uri = ($ApiBase.TrimEnd("/") + $Path)
    Headers = Get-AuthHeaders
    SkipHttpErrorCheck = $true
  }
  if ($null -ne $Body) {
    $parameters.ContentType = "application/json"
    $parameters.Body = ConvertTo-SafeJson $Body
  }
  $response = Invoke-WebRequest @parameters
  $content = ($response.Content | Out-String).Trim()
  $body = if ([string]::IsNullOrWhiteSpace($content)) {
    [pscustomobject]@{ ok = $false; error = "empty_response"; token_printed = $false }
  } else {
    $content | ConvertFrom-Json
  }
  [pscustomobject]@{ status_code = [int]$response.StatusCode; body = $body }
}

function Invoke-MatlabDoctor {
  param([ValidateSet("preview", "apply", "status", "safe-summary")] [string]$DoctorCommand, [switch]$WithConfirm)
  $doctorPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"
  $outputDir = ".agent/tmp/matlab-golden-trial/$TaskId"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $doctorPath,
    "-Command",
    $DoctorCommand,
    "-OutputDir",
    $outputDir,
    "-Json"
  )
  if ($WithConfirm) {
    $args += "-Confirm"
    $args += @("-ConfirmationText", $DoctorConfirmationPhrase)
  }
  $raw = & pwsh @args
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Invoke-MatlabRunner {
  param([string]$RunnerCommand, [switch]$WithConfirm)
  $runnerPath = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
  $outputDir = ".agent/tmp/matlab-golden-trial/$TaskId"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $runnerPath,
    "-Command",
    $RunnerCommand,
    "-TaskId",
    $TaskId,
    "-WorkerId",
    $WorkerId,
    "-OutputDir",
    $outputDir,
    "-Json"
  )
  if ($WithConfirm) {
    $args += "-Confirm"
    $args += @("-ConfirmationText", $RunnerConfirmationPhrase)
  }
  $raw = & pwsh @args
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-ProjectView {
  $response = Invoke-RecoveryApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.project }
  return $null
}

function Get-WorkerView {
  $response = Invoke-RecoveryApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.worker }
  return $null
}

function Get-TaskViewById {
  param([string]$RequestedTaskId)
  if ([string]::IsNullOrWhiteSpace($RequestedTaskId)) { return $null }
  $response = Invoke-RecoveryApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($RequestedTaskId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.task }
  return $null
}

function Test-TaskHasRecoveryMetadata {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  (
    [string](Get-PropertyValue $metadata "adapter") -eq "mg334-matlab-golden-recovery" -and
    [string](Get-PropertyValue $metadata "reason") -eq "mg334_one_live_matlab_recovery_trial" -and
    [string](Get-PropertyValue $metadata "source_run_id") -eq "mega-goal-334-matlab-startup-diagnostics-recovery" -and
    [string](Get-PropertyValue $metadata "template_id") -eq $TemplateIdTarget -and
    [string](Get-PropertyValue $metadata "runner_id") -eq $RunnerIdTarget
  )
}

function Get-TaskTemplateId {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  $fromMetadata = [string](Get-PropertyValue $metadata "template_id")
  if (-not [string]::IsNullOrWhiteSpace($fromMetadata)) { return $fromMetadata }
  ""
}

function Get-TaskRunnerId {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  $fromMetadata = [string](Get-PropertyValue $metadata "runner_id")
  if (-not [string]::IsNullOrWhiteSpace($fromMetadata)) { return $fromMetadata }
  if ((Get-TaskTemplateId $Task) -eq $TemplateIdTarget) { return $RunnerIdTarget }
  ""
}

function New-RecoveryTaskPayload {
  [pscustomobject]@{
    task_id = $RecoveryTaskId
    project_id = $ProjectId
    title = "MG334 MATLAB golden recovery task"
    body = "Run the fixed MG334 synthetic MATLAB recovery sweep only after MATLAB doctor passes. Grid eta=[2,3], h_km=[500], P=[6]."
    prompt_summary = "MG334 deterministic MATLAB startup recovery. Safe summary only; no raw MATLAB output."
    risk = "medium"
    source = "manual"
    task_type = "matlab-parameter-sweep"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @(
      "fixed MATLAB doctor passed before claim",
      "fixed matlab-parameter-sweep runner completed",
      "manifest summary and metrics files present",
      "evidence lists only actual existing files",
      "raw_stdout_included=false",
      "raw_stderr_included=false",
      "token_printed=false"
    )
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = @{
      adapter = "mg334-matlab-golden-recovery"
      decision = "continue"
      reason = "mg334_one_live_matlab_recovery_trial"
      task_type = "matlab-parameter-sweep"
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      evidence_schema = @($EvidenceSchemaId)
      allowed_paths = @($AllowedPaths)
      blocked_paths = @($BlockedPaths)
      validation = @(
        "fixed MATLAB doctor passed before claim",
        "fixed matlab-parameter-sweep runner completed",
        "manifest summary and metrics files present",
        "token_printed=false"
      )
      expected_files = @()
      expected_outputs = @(
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/manifest.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/summary.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/metrics.csv"
      )
      stop_criteria_status = @("complete_exact_live_matlab_recovery_trial_then_stop")
      source_run_id = "mega-goal-334-matlab-startup-diagnostics-recovery"
      supersedes_failed_task_id = $DoNotReuseTaskId
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
}

function Invoke-CreatePreview {
  $targetTaskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { $RecoveryTaskId } else { $TaskId }
  $project = Get-ProjectView
  $existing = Get-TaskViewById -RequestedTaskId $targetTaskId
  $oldFailed = Get-TaskViewById -RequestedTaskId $DoNotReuseTaskId
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($targetTaskId -ne $RecoveryTaskId) { $blockers.Add("unexpected_live_matlab_recovery_task_id") | Out-Null }
  if ($targetTaskId -eq $DoNotReuseTaskId) { $blockers.Add("mg333_failed_task_must_not_be_reused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $blockers.Add("unexpected_template_id") | Out-Null }
  if (-not $project) { $blockers.Add("project_not_found") | Out-Null }
  if ($existing -and -not (Test-TaskHasRecoveryMetadata $existing)) { $blockers.Add("existing_task_not_mg334_recovery") | Out-Null }
  if ($existing -and [string]$existing.status -notin @("queued", "completed", "failed")) { $blockers.Add("existing_task_not_safe_state") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_create_preview.v1"
    ok = ($blockers.Count -eq 0)
    mode = "preview"
    project_id = $ProjectId
    task_id = $targetTaskId
    previous_failed_task_id = $DoNotReuseTaskId
    previous_failed_task_seen = [bool]$oldFailed
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_exists = [bool]$existing
    would_create_task = -not [bool]$existing -and $blockers.Count -eq 0
    task_created = $false
    blockers = @($blockers)
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    required_capabilities = @($RequiredCapabilities)
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Invoke-CreateApply {
  $preview = Invoke-CreatePreview
  if (-not $preview.ok) {
    return [pscustomobject]@{
      schema = "skybridge.live_matlab_golden_recovery_create_result.v1"
      ok = $false
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      task_created = $false
      review_reason = "create_preconditions_failed"
      blockers = @($preview.blockers)
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  if (-not $Confirm -or $ConfirmationText -ne $CreateConfirmationPhrase) {
    return [pscustomobject]@{
      schema = "skybridge.live_matlab_golden_recovery_create_result.v1"
      ok = $false
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      task_created = $false
      review_reason = "missing_exact_confirmation"
      blockers = @("missing_exact_confirmation")
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  if ($preview.task_exists) {
    return [pscustomobject]@{
      schema = "skybridge.live_matlab_golden_recovery_create_result.v1"
      ok = $true
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      task_created = $false
      task_already_present = $true
      review_reason = "existing_mg334_recovery_task_reused_without_requeue"
      blockers = @()
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  $response = Invoke-RecoveryApi -Method POST -Path "/v1/tasks" -Body (New-RecoveryTaskPayload)
  $created = ($response.status_code -ge 200 -and $response.status_code -lt 300)
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_create_result.v1"
    ok = $created
    mode = "apply"
    project_id = $ProjectId
    task_id = $preview.task_id
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_created = $created
    task_status = if ($created) { [string]$response.body.task.status } else { "unknown" }
    review_reason = if ($created) { "exact_confirmation_received_created_one_live_matlab_recovery_task" } else { "task_create_failed" }
    blockers = if ($created) { @() } else { @("task_create_failed") }
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Test-RunEligibility {
  param($Task, $Worker, $RunnerPreview, $DoctorPreview)
  $reasons = New-Object System.Collections.Generic.List[string]
  $template = if ($Task) { Get-TaskTemplateId $Task } else { "" }
  $runner = if ($Task) { Get-TaskRunnerId $Task } else { "" }
  $allowedOk = $false
  $blockedOk = $false
  $workerStatus = "unknown"

  if ([string]::IsNullOrWhiteSpace($WorkerId) -or $WorkerId -ne $WorkerIdTarget) { $reasons.Add("worker_id_must_be_jerry_win_local_01") | Out-Null }
  if ($TaskId -ne $RecoveryTaskId) { $reasons.Add("unexpected_live_matlab_recovery_task_id") | Out-Null }
  if ($TaskId -eq $DoNotReuseTaskId) { $reasons.Add("mg333_failed_task_must_not_be_reused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $reasons.Add("unexpected_template_id") | Out-Null }

  if ($Task) {
    if ([string]$Task.task_id -ne $RecoveryTaskId) { $reasons.Add("selected_task_id_mismatch") | Out-Null }
    if ([string]$Task.project_id -ne $ProjectId) { $reasons.Add("project_id_mismatch") | Out-Null }
    if ([string]$Task.status -ne "queued") {
      if ([string]$Task.status -in @("completed", "cancelled", "blocked", "failed")) { $reasons.Add("target_task_terminal_or_blocked") | Out-Null }
      else { $reasons.Add("target_task_not_queued") | Out-Null }
    }
    if ([string]$Task.risk -notin @("low", "medium")) { $reasons.Add("risk_not_low_or_medium") | Out-Null }
    if ($template -ne $TemplateIdTarget) { $reasons.Add("template_not_supported_mg334_recovery") | Out-Null }
    if ($runner -ne $RunnerIdTarget) { $reasons.Add("runner_not_supported_mg334_recovery") | Out-Null }
    if ($Task.lease -and [string]$Task.lease.lease_status -eq "active") { $reasons.Add("active_lease_exists") | Out-Null }
    if ($Task.claim) { $reasons.Add("existing_claim_residue") | Out-Null }
    if (-not (Test-TaskHasRecoveryMetadata $Task)) { $reasons.Add("task_not_created_by_mg334_recovery") | Out-Null }

    $required = @(ConvertTo-Array $Task.required_capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $required $RequiredCapabilities)) { $reasons.Add("task_missing_matlab_recovery_required_capabilities") | Out-Null }
    if ($required -contains "codex") { $reasons.Add("codex_capability_rejected_mg334") | Out-Null }

    $allowed = @(ConvertTo-Array $Task.allowed_paths | ForEach-Object { [string]$_ })
    $blocked = @(ConvertTo-Array $Task.blocked_paths | ForEach-Object { [string]$_ })
    $allowedOk = $allowed.Count -gt 0 -and (Test-Subset $allowed $AllowedPaths)
    $blockedOk = Test-ContainsAll $blocked $BlockedPaths
    if (-not $allowedOk) { $reasons.Add("allowed_paths_outside_matlab_recovery_policy") | Out-Null }
    if (-not $blockedOk) { $reasons.Add("blocked_paths_missing_matlab_recovery_policy") | Out-Null }

    $text = @([string]$Task.title, [string]$Task.body, [string]$Task.prompt_summary, ($allowed -join " ")) -join " "
    if (Test-UnsafeText $text) { $reasons.Add("unsafe_path_or_text_detected") | Out-Null }
  } else {
    $reasons.Add("target_task_not_found") | Out-Null
  }

  if (-not $Worker) {
    $reasons.Add("worker_not_registered_or_offline") | Out-Null
  } else {
    $workerStatus = [string]$Worker.status
    if ($Worker.status -ne "online") { $reasons.Add("worker_not_online") | Out-Null }
    if ($Worker.enabled -ne $true) { $reasons.Add("worker_disabled") | Out-Null }
    $workerCapabilities = @(ConvertTo-Array $Worker.capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $workerCapabilities $RequiredCapabilities)) { $reasons.Add("worker_missing_matlab_recovery_required_capabilities") | Out-Null }
  }

  if ($RunnerPreview.ok -ne $true) { $reasons.Add("runner_preview_blocked") | Out-Null }
  if ($RunnerPreview.combination_count -ne 2) { $reasons.Add("unexpected_parameter_grid_size") | Out-Null }
  if ($DoctorPreview.fixed_script_visible -ne $true) { $reasons.Add("doctor_fixed_script_missing") | Out-Null }

  [pscustomobject]@{
    task = $Task
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    eligible = ($reasons.Count -eq 0)
    rejected_reason = (($reasons | Select-Object -Unique) -join ";")
    allowed_paths_checked = $allowedOk
    blocked_paths_checked = $blockedOk
    cloud_worker_status = $workerStatus
    runner_preview = $RunnerPreview
    doctor_preview = $DoctorPreview
  }
}

function New-RunRecord {
  param(
    [ValidateSet("preview", "apply")]
    [string]$Mode,
    [bool]$Ok,
    $Eligibility,
    [bool]$ClaimCreated = $false,
    [bool]$ExecutionStarted = $false,
    [bool]$ExecutionCompleted = $false,
    [bool]$ExecutionFailed = $false,
    [string]$FinalTaskState = "",
    $Evidence = $null,
    $Doctor = $null,
    [string]$ResultSummary = ""
  )
  [pscustomobject]@{
    schema = if ($Mode -eq "apply") { "skybridge.live_matlab_golden_recovery_run_result.v1" } else { "skybridge.live_matlab_golden_recovery_run_preview.v1" }
    ok = $Ok
    mode = $Mode
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = $TaskId
    expected_task_id = $RecoveryTaskId
    previous_failed_task_id = $DoNotReuseTaskId
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    evidence_schema = $EvidenceSchemaId
    selected = [bool]($Eligibility.task)
    eligible = [bool]$Eligibility.eligible
    selected_task_count = if ($Eligibility.task) { 1 } else { 0 }
    rejected_reason = [string]$Eligibility.rejected_reason
    doctor_present = [bool]$Doctor
    doctor_ok = if ($Doctor) { [bool]$Doctor.ok } else { $false }
    doctor_failure_category = if ($Doctor) { [string]$Doctor.failure_category } else { "" }
    claim_created = $ClaimCreated
    task_claimed_count = if ($ClaimCreated) { 1 } else { 0 }
    old_task_claimed = $false
    execution_started = $ExecutionStarted
    execution_completed = $ExecutionCompleted
    execution_failed = $ExecutionFailed
    evidence_present = [bool]$Evidence
    evidence = $Evidence
    allowed_paths_checked = [bool]$Eligibility.allowed_paths_checked
    blocked_paths_checked = [bool]$Eligibility.blocked_paths_checked
    changed_files = if ($Evidence) { @($Evidence.changed_files) } else { @() }
    existing_outputs = if ($Evidence) { @($Evidence.existing_outputs) } else { @() }
    expected_outputs_missing = if ($Evidence) { @($Evidence.expected_outputs_missing) } else { @() }
    validation_status = if ($Evidence) { [string]$Evidence.validation_status } elseif ($Ok) { "preview_only" } else { "blocked" }
    result_summary = if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) { $ResultSummary } elseif ($Ok) { "MG334 exact MATLAB recovery task is eligible for fixed-runner apply after doctor passes." } else { "MG334 MATLAB recovery task is not eligible for live apply." }
    final_task_state = $FinalTaskState
    cloud_worker_status = [string]$Eligibility.cloud_worker_status
    matlab_invoked = if ($Evidence) { [bool]$Evidence.matlab_invoked } else { $false }
    matlab_exit_code = if ($Evidence) { $Evidence.matlab_exit_code } else { $null }
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    pr_created = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Invoke-RunPreview {
  if ($TaskId -ne $RecoveryTaskId) {
    $dummy = [pscustomobject]@{
      task = $null
      eligible = $false
      rejected_reason = "unexpected_live_matlab_recovery_task_id"
      allowed_paths_checked = $false
      blocked_paths_checked = $false
      cloud_worker_status = "unknown"
    }
    return New-RunRecord -Mode preview -Ok $false -Eligibility $dummy
  }
  $worker = Get-WorkerView
  $task = Get-TaskViewById -RequestedTaskId $TaskId
  $runnerPreview = Invoke-MatlabRunner -RunnerCommand "preview"
  $doctorPreview = Invoke-MatlabDoctor -DoctorCommand "preview"
  $eligibility = Test-RunEligibility -Task $task -Worker $worker -RunnerPreview $runnerPreview -DoctorPreview $doctorPreview
  New-RunRecord -Mode preview -Ok ([bool]$eligibility.eligible) -Eligibility $eligibility -Doctor $doctorPreview
}

function Invoke-RunApply {
  $preview = Invoke-RunPreview
  if (-not $preview.ok) { return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $preview -ResultSummary $preview.result_summary }
  if (-not $Confirm -or $ConfirmationText -ne $RunConfirmationPhrase) {
    $preview.rejected_reason = "missing_exact_confirmation"
    $preview.eligible = $true
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ResultSummary "Exact MG334 run confirmation is required before claim/start/MATLAB recovery apply."
  }

  $doctor = Invoke-MatlabDoctor -DoctorCommand "apply" -WithConfirm
  if ($doctor.ok -ne $true) {
    $preview.rejected_reason = if (-not [string]::IsNullOrWhiteSpace([string]$doctor.failure_category)) { [string]$doctor.failure_category } else { "matlab_doctor_failed" }
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $doctor -ResultSummary "MATLAB doctor failed; no live recovery task was claimed."
  }

  $claim = Invoke-RecoveryApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -Body @{ worker_id = $WorkerId }
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    $preview.rejected_reason = "claim_failed"
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $doctor -ResultSummary "Task claim failed before MATLAB runner invocation."
  }

  $start = Invoke-RecoveryApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -Body @{ worker_id = $WorkerId }
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    $preview.rejected_reason = "start_failed"
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionFailed $true -Doctor $doctor -ResultSummary "Task start failed after claim."
  }

  $runner = Invoke-MatlabRunner -RunnerCommand "apply" -WithConfirm
  $evidence = $runner.evidence
  if (-not $evidence) {
    $evidence = [pscustomobject]@{
      schema = $EvidenceSchemaId
      ok = $false
      task_id = $TaskId
      worker_id = $WorkerId
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      validation_status = "failed"
      changed_files = @()
      existing_outputs = @()
      expected_outputs_missing = @(
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/manifest.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/summary.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-334-001/metrics.csv"
      )
      failure_category = "matlab_runner_no_evidence"
      result_summary = "MATLAB runner returned no evidence."
      matlab_invoked = $false
      matlab_exit_code = $null
      raw_stdout_included = $false
      raw_stderr_included = $false
      raw_mat_files_uploaded = $false
      token_printed = $false
    }
  }

  $finishBody = @{
    worker_id = $WorkerId
    summary = [string]$evidence.result_summary
    evidence_summary = @{
      task_id = $TaskId
      changed_files = @($evidence.changed_files)
      existing_outputs = @($evidence.existing_outputs)
      expected_outputs_missing = @($evidence.expected_outputs_missing)
      validation_status = [string]$evidence.validation_status
      failure_category = [string]$evidence.failure_category
      risk_status = "medium_fixed_matlab_recovery_trial"
      summary = [string]$evidence.result_summary
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
  if ($runner.ok -eq $true) {
    $complete = Invoke-RecoveryApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -Body $finishBody
    if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
      Invoke-RecoveryApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
      return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -Doctor $doctor -FinalTaskState "failed" -ResultSummary "MATLAB evidence was produced but task completion failed; fail was attempted."
    }
    $finalTask = Get-TaskViewById -RequestedTaskId $TaskId
    return New-RunRecord -Mode apply -Ok $true -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionCompleted $true -Evidence $evidence -Doctor $doctor -FinalTaskState ([string]$finalTask.status) -ResultSummary ([string]$evidence.result_summary)
  }

  Invoke-RecoveryApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
  $failedTask = Get-TaskViewById -RequestedTaskId $TaskId
  New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -Doctor $doctor -FinalTaskState ([string]$failedTask.status) -ResultSummary ([string]$evidence.result_summary)
}

function Get-RecoveryStatus {
  $version = Invoke-RecoveryApi -Method GET -Path "/v1/version"
  $worker = Invoke-RecoveryApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-RecoveryApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $doctor = Invoke-MatlabDoctor -DoctorCommand "status"
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_status.v1"
    ok = -not [string]::IsNullOrWhiteSpace($ApiBase)
    api_base_configured = -not [string]::IsNullOrWhiteSpace($ApiBase)
    api_base_host = if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { ([uri]$ApiBase).Host } else { "" }
    token_file_present = (-not [string]::IsNullOrWhiteSpace($TokenFile) -and (Test-Path -LiteralPath $TokenFile -PathType Leaf))
    token_value_printed = $false
    worker_id = $WorkerId
    expected_worker_id = $WorkerIdTarget
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    project_id = $ProjectId
    task_id = $TaskId
    previous_failed_task_id = $DoNotReuseTaskId
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    task_status = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { [string]$task.body.task.status } else { "missing" }
    matlab_detected = [bool]$doctor.matlab_detected
    doctor_fixed_script_visible = [bool]$doctor.fixed_script_visible
    version_seen = ($version.status_code -ge 200 -and $version.status_code -lt 300)
    version_commit_sha = if ($version.status_code -ge 200 -and $version.status_code -lt 300) { [string]$version.body.commit_sha } else { "" }
    confirmation_required_doctor = $true
    confirmation_text_doctor = $DoctorConfirmationPhrase
    confirmation_required_create = $true
    confirmation_text_create = $CreateConfirmationPhrase
    confirmation_required_run = $true
    confirmation_text_run = $RunConfirmationPhrase
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Get-RecoveryReport {
  $worker = Invoke-RecoveryApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-RecoveryApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $taskBody = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { $task.body.task } else { $null }
  $evidenceSummary = if ($taskBody -and $taskBody.result) { $taskBody.result.evidence_summary } else { $null }
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_report.v1"
    ok = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    worker_id = $WorkerId
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    task_id = $TaskId
    previous_failed_task_id = $DoNotReuseTaskId
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    final_task_state = if ($taskBody) { [string]$taskBody.status } else { "missing" }
    assigned_worker_id = if ($taskBody) { [string]$taskBody.assigned_worker_id } else { "" }
    evidence_summary_present = [bool]$evidenceSummary
    evidence_summary = $evidenceSummary
    task_claimed_count = if ($taskBody -and $taskBody.claim) { 1 } else { 0 }
    old_task_claimed = $false
    claim_created = if ($taskBody -and $taskBody.claim) { $true } else { $false }
    execution_started = if ($taskBody -and [string]$taskBody.status -in @("running", "completed", "failed")) { $true } else { $false }
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

if ($Command -eq "status") {
  $result = Get-RecoveryStatus
} elseif ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_safe_summary.v1"
    ok = $true
    worker_id = $WorkerId
    task_id = $TaskId
    previous_failed_task_id = $DoNotReuseTaskId
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    next_safe_action = "doctor_preview_then_exact_confirm_doctor_apply_then_create_and_run_exact_recovery_task_if_doctor_passes"
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
} elseif ($Command -eq "doctor-preview") {
  $result = Invoke-MatlabDoctor -DoctorCommand "preview"
} elseif ($Command -eq "doctor-apply") {
  if (-not $Confirm -or $ConfirmationText -ne $DoctorConfirmationPhrase) {
    $result = [pscustomobject]@{
      schema = "skybridge.matlab_doctor.v1"
      ok = $false
      mode = "apply"
      matlab_detected = $false
      matlab_executable = ""
      matlab_version_summary = ""
      batch_supported = $false
      startup_ok = $false
      license_ok = $false
      license_status = "not_checked"
      fixed_script_visible = $true
      output_dir = ".agent/tmp/matlab-golden-trial/$TaskId"
      doctor_summary_path = ".agent/tmp/matlab-golden-trial/$TaskId/doctor_summary.json"
      doctor_metrics_path = ".agent/tmp/matlab-golden-trial/$TaskId/doctor_metrics.csv"
      output_write_ok = $false
      minimal_compute_ok = $false
      matlab_invoked = $false
      failure_category = "missing_exact_confirmation"
      failure_summary = "Exact confirmation is required before MATLAB startup diagnostic apply."
      blockers = @("missing_exact_confirmation")
      warnings = @()
      claim_created = $false
      execution_started = $false
      codex_run_called = $false
      arbitrary_shell_enabled = $false
      worker_loop_started = $false
      project_control_unpaused = $false
      raw_stdout_included = $false
      raw_stderr_included = $false
      token_printed = $false
    }
  } else {
    $result = Invoke-MatlabDoctor -DoctorCommand "apply" -WithConfirm
  }
} elseif ($Command -eq "preview-create") {
  $result = Invoke-CreatePreview
} elseif ($Command -eq "apply-create") {
  $result = Invoke-CreateApply
} elseif ($Command -eq "preview-run") {
  $result = Invoke-RunPreview
} elseif ($Command -eq "apply-run") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_recovery_apply_run.v1"
    ok = $false
    runner_result = Invoke-RunApply
    report = $null
    task_id = $TaskId
    worker_id = $WorkerId
    token_printed = $false
  }
  $result.ok = [bool]$result.runner_result.ok
  $result.report = Get-RecoveryReport
  $result | Add-Member -NotePropertyName task_claimed_count -NotePropertyValue ([int]$result.runner_result.task_claimed_count)
  $result | Add-Member -NotePropertyName old_task_claimed -NotePropertyValue $false
  $result | Add-Member -NotePropertyName claim_created -NotePropertyValue ([bool]$result.runner_result.claim_created)
  $result | Add-Member -NotePropertyName execution_started -NotePropertyValue ([bool]$result.runner_result.execution_started)
  $result | Add-Member -NotePropertyName execution_completed -NotePropertyValue ([bool]$result.runner_result.execution_completed)
  $result | Add-Member -NotePropertyName execution_failed -NotePropertyValue ([bool]$result.runner_result.execution_failed)
  $result | Add-Member -NotePropertyName matlab_invoked -NotePropertyValue ([bool]$result.runner_result.matlab_invoked)
  $result | Add-Member -NotePropertyName codex_run_called -NotePropertyValue $false
  $result | Add-Member -NotePropertyName arbitrary_shell_enabled -NotePropertyValue $false
  $result | Add-Member -NotePropertyName worker_loop_started -NotePropertyValue $false
  $result | Add-Member -NotePropertyName unbounded_run_enabled -NotePropertyValue $false
  $result | Add-Member -NotePropertyName project_control_unpaused -NotePropertyValue $false
} else {
  $result = Get-RecoveryReport
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
