param(
  [ValidateSet("status", "doctor-preview", "doctor-apply", "preview-create", "apply-create", "preview-run", "apply-run", "report", "safe-summary")]
  [string]$Command = "status",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "live-matlab-golden-task-336-001",
  [string]$TemplateId = "matlab-parameter-sweep.v1",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SuccessTaskId = "live-matlab-golden-task-336-001"
$DoNotReuseTaskIds = @("live-matlab-golden-task-333-001", "live-matlab-golden-task-334-001")
$WorkerIdTarget = "jerry-win-local-01"
$TemplateIdTarget = "matlab-parameter-sweep.v1"
$RunnerIdTarget = "matlab-parameter-sweep-runner.v1"
$EvidenceSchemaId = "skybridge.matlab_sweep_evidence.v1"
$DoctorConfirmationPhrase = "I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY"
$CreateConfirmationPhrase = "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY"
$RunConfirmationPhrase = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY"
$HeartbeatConfirmationPhrase = "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM"
$RunnerConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY"
$RequiredCapabilities = @("windows", "powershell", "matlab")
$AllowedPaths = @(".agent/tmp/matlab-golden-trial/**", "results/skybridge/matlab-golden-trial/**")
$BlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 32
}

function ConvertTo-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  @($Value)
}

function Get-PropertyValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  $null
}

function Test-ContainsAll {
  param([string[]]$Actual, [string[]]$Required)
  foreach ($item in $Required) {
    if ($Actual -notcontains $item) { return $false }
  }
  $true
}

function Test-Subset {
  param([string[]]$Actual, [string[]]$Allowed)
  foreach ($item in $Actual) {
    if ($Allowed -notcontains $item) { return $false }
  }
  $true
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

function Invoke-SuccessApi {
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

function Invoke-HeartbeatRefresh {
  $heartbeatPath = Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1"
  if (-not (Test-Path -LiteralPath $heartbeatPath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; cloud_worker_status = "unknown"; review_reason = "heartbeat_script_missing"; token_printed = $false }
  }
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $heartbeatPath,
    "-Command",
    "apply",
    "-ApiBase",
    $ApiBase,
    "-TokenFile",
    $TokenFile,
    "-WorkerId",
    $WorkerId,
    "-Confirm",
    "-ConfirmationText",
    $HeartbeatConfirmationPhrase,
    "-Json"
  )
  $raw = & pwsh @args
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-ProjectView {
  $response = Invoke-SuccessApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.project }
  $null
}

function Get-WorkerView {
  $response = Invoke-SuccessApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.worker }
  $null
}

function Get-TaskViewById {
  param([string]$RequestedTaskId)
  if ([string]::IsNullOrWhiteSpace($RequestedTaskId)) { return $null }
  $response = Invoke-SuccessApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($RequestedTaskId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.task }
  $null
}

function Test-TaskHasSuccessMetadata {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  (
    [string](Get-PropertyValue $metadata "adapter") -eq "mg336-matlab-golden-success" -and
    [string](Get-PropertyValue $metadata "reason") -eq "mg336_one_live_matlab_success_trial" -and
    [string](Get-PropertyValue $metadata "source_run_id") -eq "mega-goal-336-matlab-golden-recovery-success" -and
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

function New-SuccessTaskPayload {
  [pscustomobject]@{
    task_id = $SuccessTaskId
    project_id = $ProjectId
    title = "MG336 MATLAB golden recovery success task"
    body = "Run the fixed MG336 synthetic MATLAB parameter sweep only after MATLAB doctor passes. Grid eta=[2,3], h_km=[500], P=[6]."
    prompt_summary = "MG336 deterministic MATLAB golden recovery success. Safe summary only; no raw MATLAB output."
    risk = "medium"
    source = "manual"
    task_type = "matlab-parameter-sweep"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @(
      "fixed MATLAB doctor passed before claim",
      "fixed matlab-parameter-sweep runner completed",
      "manifest summary and metrics files present",
      "tiny synthetic grid has exactly two combinations",
      "server evidence lists only actual existing files",
      "raw_stdout_included=false",
      "raw_stderr_included=false",
      "token_printed=false"
    )
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = @{
      adapter = "mg336-matlab-golden-success"
      decision = "continue"
      reason = "mg336_one_live_matlab_success_trial"
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
        "tiny synthetic grid has exactly two combinations",
        "token_printed=false"
      )
      expected_outputs = @(
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json",
        ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv"
      )
      stop_criteria_status = @("complete_exact_live_matlab_success_trial_then_stop")
      source_run_id = "mega-goal-336-matlab-golden-recovery-success"
      supersedes_failed_task_ids = @($DoNotReuseTaskIds)
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
}

function Invoke-CreatePreview {
  $targetTaskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { $SuccessTaskId } else { $TaskId }
  $project = Get-ProjectView
  $existing = Get-TaskViewById -RequestedTaskId $targetTaskId
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($targetTaskId -ne $SuccessTaskId) { $blockers.Add("unexpected_live_matlab_success_task_id") | Out-Null }
  if ($DoNotReuseTaskIds -contains $targetTaskId) { $blockers.Add("mg333_mg334_failed_tasks_must_not_be_reused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $blockers.Add("unexpected_template_id") | Out-Null }
  if (-not $project) { $blockers.Add("project_not_found") | Out-Null }
  if ($existing -and -not (Test-TaskHasSuccessMetadata $existing)) { $blockers.Add("existing_task_not_mg336_success") | Out-Null }
  if ($existing -and [string]$existing.status -notin @("queued", "completed", "failed")) { $blockers.Add("existing_task_not_safe_state") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_success_create_preview.v1"
    ok = ($blockers.Count -eq 0)
    mode = "preview"
    project_id = $ProjectId
    task_id = $targetTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskIds)
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
      schema = "skybridge.live_matlab_golden_success_create_result.v1"
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
      schema = "skybridge.live_matlab_golden_success_create_result.v1"
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
      schema = "skybridge.live_matlab_golden_success_create_result.v1"
      ok = $true
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      task_created = $false
      task_already_present = $true
      review_reason = "existing_mg336_success_task_reused_without_requeue"
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
  $response = Invoke-SuccessApi -Method POST -Path "/v1/tasks" -Body (New-SuccessTaskPayload)
  $created = ($response.status_code -ge 200 -and $response.status_code -lt 300)
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_success_create_result.v1"
    ok = $created
    mode = "apply"
    project_id = $ProjectId
    task_id = $preview.task_id
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_created = $created
    task_status = if ($created) { [string]$response.body.task.status } else { "unknown" }
    review_reason = if ($created) { "exact_confirmation_received_created_one_live_matlab_success_task" } else { "task_create_failed" }
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
  if ($TaskId -ne $SuccessTaskId) { $reasons.Add("unexpected_live_matlab_success_task_id") | Out-Null }
  if ($DoNotReuseTaskIds -contains $TaskId) { $reasons.Add("mg333_mg334_failed_tasks_must_not_be_reused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $reasons.Add("unexpected_template_id") | Out-Null }

  if ($Task) {
    if ([string]$Task.task_id -ne $SuccessTaskId) { $reasons.Add("selected_task_id_mismatch") | Out-Null }
    if ([string]$Task.project_id -ne $ProjectId) { $reasons.Add("project_id_mismatch") | Out-Null }
    if ([string]$Task.status -ne "queued") {
      if ([string]$Task.status -in @("completed", "cancelled", "blocked", "failed")) { $reasons.Add("target_task_terminal_or_blocked") | Out-Null }
      else { $reasons.Add("target_task_not_queued") | Out-Null }
    }
    if ([string]$Task.risk -notin @("low", "medium")) { $reasons.Add("risk_not_low_or_medium") | Out-Null }
    if ($template -ne $TemplateIdTarget) { $reasons.Add("template_not_supported_mg336_success") | Out-Null }
    if ($runner -ne $RunnerIdTarget) { $reasons.Add("runner_not_supported_mg336_success") | Out-Null }
    if ($Task.lease -and [string]$Task.lease.lease_status -eq "active") { $reasons.Add("active_lease_exists") | Out-Null }
    if ($Task.claim) { $reasons.Add("existing_claim_residue") | Out-Null }
    if (-not (Test-TaskHasSuccessMetadata $Task)) { $reasons.Add("task_not_created_by_mg336_success") | Out-Null }

    $required = @(ConvertTo-Array $Task.required_capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $required $RequiredCapabilities)) { $reasons.Add("task_missing_matlab_success_required_capabilities") | Out-Null }
    if ($required -contains "codex") { $reasons.Add("codex_capability_rejected_mg336") | Out-Null }

    $allowed = @(ConvertTo-Array $Task.allowed_paths | ForEach-Object { [string]$_ })
    $blocked = @(ConvertTo-Array $Task.blocked_paths | ForEach-Object { [string]$_ })
    $allowedOk = $allowed.Count -gt 0 -and (Test-Subset $allowed $AllowedPaths)
    $blockedOk = Test-ContainsAll $blocked $BlockedPaths
    if (-not $allowedOk) { $reasons.Add("allowed_paths_outside_matlab_success_policy") | Out-Null }
    if (-not $blockedOk) { $reasons.Add("blocked_paths_missing_matlab_success_policy") | Out-Null }

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
    if (-not (Test-ContainsAll $workerCapabilities $RequiredCapabilities)) { $reasons.Add("worker_missing_matlab_success_required_capabilities") | Out-Null }
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

function Test-DoctorPassed {
  param($Doctor)
  (
    $Doctor -and
    $Doctor.ok -eq $true -and
    $Doctor.startup_ok -eq $true -and
    [string]$Doctor.license_status -eq "available" -and
    $Doctor.minimal_compute_ok -eq $true
  )
}

function Test-SuccessEvidencePassed {
  param($Evidence)
  (
    $Evidence -and
    $Evidence.ok -eq $true -and
    [string]$Evidence.validation_status -eq "passed" -and
    [int]$Evidence.completed_count -eq 2 -and
    [int]$Evidence.failed_count -eq 0 -and
    ([int]$Evidence.expected_combination_count -eq 2 -or ($null -eq $Evidence.expected_combination_count -and [int]$Evidence.combination_count -eq 2)) -and
    $Evidence.manifest_exists -eq $true -and
    $Evidence.summary_exists -eq $true -and
    $Evidence.metrics_exists -eq $true -and
    @($Evidence.changed_files).Count -eq 3 -and
    @($Evidence.expected_outputs_missing).Count -eq 0 -and
    $Evidence.raw_stdout_included -eq $false -and
    $Evidence.raw_stderr_included -eq $false -and
    $Evidence.token_printed -eq $false
  )
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
    $HeartbeatRefresh = $null,
    [string]$ResultSummary = ""
  )
  [pscustomobject]@{
    schema = if ($Mode -eq "apply") { "skybridge.live_matlab_golden_success_run_result.v1" } else { "skybridge.live_matlab_golden_success_run_preview.v1" }
    ok = $Ok
    mode = $Mode
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = $TaskId
    expected_task_id = $SuccessTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskIds)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    evidence_schema = $EvidenceSchemaId
    selected = [bool]$Eligibility.task
    eligible = [bool]$Eligibility.eligible
    selected_task_count = if ($Eligibility.task) { 1 } else { 0 }
    rejected_reason = [string]$Eligibility.rejected_reason
    doctor_present = [bool]$Doctor
    doctor_ok = if ($Doctor) { [bool]$Doctor.ok } else { $false }
    doctor_precondition_passed = if ($Doctor) { Test-DoctorPassed $Doctor } else { $false }
    doctor_failure_category = if ($Doctor) { [string]$Doctor.failure_category } else { "" }
    heartbeat_refresh_attempted = [bool]$HeartbeatRefresh
    heartbeat_refresh_ok = if ($HeartbeatRefresh) { [bool]$HeartbeatRefresh.ok } else { $false }
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
    result_summary = if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) { $ResultSummary } elseif ($Ok) { "MG336 exact MATLAB success task is eligible for fixed-runner apply after doctor passes." } else { "MG336 MATLAB success task is not eligible for live apply." }
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
  if ($TaskId -ne $SuccessTaskId -or ($DoNotReuseTaskIds -contains $TaskId)) {
    $dummy = [pscustomobject]@{
      task = $null
      eligible = $false
      rejected_reason = if ($DoNotReuseTaskIds -contains $TaskId) { "mg333_mg334_failed_tasks_must_not_be_reused" } else { "unexpected_live_matlab_success_task_id" }
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

function Get-PostHeartbeatEligibility {
  $worker = Get-WorkerView
  $task = Get-TaskViewById -RequestedTaskId $TaskId
  $runnerPreview = Invoke-MatlabRunner -RunnerCommand "preview"
  $doctorPreview = Invoke-MatlabDoctor -DoctorCommand "preview"
  Test-RunEligibility -Task $task -Worker $worker -RunnerPreview $runnerPreview -DoctorPreview $doctorPreview
}

function New-FailureEvidence {
  param([string]$Category, [string]$Summary)
  $runnerPreview = Invoke-MatlabRunner -RunnerCommand "preview"
  [pscustomobject]@{
    schema = $EvidenceSchemaId
    ok = $false
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    parameter_grid_summary = [string]$runnerPreview.parameter_grid_summary
    combination_count = 2
    expected_combination_count = 2
    completed_count = 0
    failed_count = 2
    output_dir = [string]$runnerPreview.output_dir
    manifest_path = [string]$runnerPreview.manifest_path
    manifest_exists = $false
    summary_path = [string]$runnerPreview.summary_path
    summary_exists = $false
    metrics_path = [string]$runnerPreview.metrics_path
    metrics_exists = $false
    validation_status = "failed"
    matlab_invoked = $false
    matlab_exit_code = $null
    started_at = $null
    completed_at = $null
    failed_at = (Get-Date).ToUniversalTime().ToString("o")
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    changed_files = @()
    existing_outputs = @()
    expected_outputs_missing = @($runnerPreview.manifest_path, $runnerPreview.summary_path, $runnerPreview.metrics_path)
    failure_category = $Category
    result_summary = $Summary
    pr_created = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    token_printed = $false
  }
}

function Get-FinishBody {
  param($Evidence)
  @{
    worker_id = $WorkerId
    summary = [string]$Evidence.result_summary
    evidence_summary = @{
      schema = $EvidenceSchemaId
      task_id = $TaskId
      worker_id = $WorkerId
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      matlab_invoked = [bool]$Evidence.matlab_invoked
      matlab_exit_code = $Evidence.matlab_exit_code
      parameter_grid_summary = [string]$Evidence.parameter_grid_summary
      expected_combination_count = 2
      combination_count = [int]$Evidence.combination_count
      completed_count = [int]$Evidence.completed_count
      failed_count = [int]$Evidence.failed_count
      manifest_path = [string]$Evidence.manifest_path
      manifest_exists = [bool]$Evidence.manifest_exists
      summary_path = [string]$Evidence.summary_path
      summary_exists = [bool]$Evidence.summary_exists
      metrics_path = [string]$Evidence.metrics_path
      metrics_exists = [bool]$Evidence.metrics_exists
      changed_files = @($Evidence.changed_files)
      existing_outputs = @($Evidence.existing_outputs)
      expected_outputs_missing = @($Evidence.expected_outputs_missing)
      validation_status = [string]$Evidence.validation_status
      failure_category = [string]$Evidence.failure_category
      risk_status = "medium_fixed_matlab_success_trial"
      summary = [string]$Evidence.result_summary
      raw_stdout_included = $false
      raw_stderr_included = $false
      codex_run_called = $false
      arbitrary_shell_enabled = $false
      worker_loop_started = $false
      project_control_unpaused = $false
      token_printed = $false
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
}

function Invoke-RunApply {
  $preview = Invoke-RunPreview
  if (-not $Confirm -or $ConfirmationText -ne $RunConfirmationPhrase) {
    $preview.rejected_reason = "missing_exact_confirmation"
    if ($preview.ok) { $preview.eligible = $true }
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ResultSummary "Exact MG336 run confirmation is required before claim/start/MATLAB success apply."
  }

  $heartbeat = $null
  if (-not $preview.ok -and [string]$preview.rejected_reason -match "worker_not_online|worker_not_registered_or_offline") {
    $heartbeat = Invoke-HeartbeatRefresh
    $postHeartbeat = Get-PostHeartbeatEligibility
    if (-not $postHeartbeat.eligible) {
      return New-RunRecord -Mode apply -Ok $false -Eligibility $postHeartbeat -HeartbeatRefresh $heartbeat -ResultSummary "Worker heartbeat refresh did not leave the exact MG336 task eligible; no claim was created."
    }
    $preview = New-RunRecord -Mode preview -Ok $true -Eligibility $postHeartbeat
  }
  if (-not $preview.ok) { return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $preview -HeartbeatRefresh $heartbeat -ResultSummary $preview.result_summary }

  $doctor = Invoke-MatlabDoctor -DoctorCommand "apply" -WithConfirm
  if (-not (Test-DoctorPassed $doctor)) {
    $preview.rejected_reason = if (-not [string]::IsNullOrWhiteSpace([string]$doctor.failure_category)) { [string]$doctor.failure_category } else { "matlab_doctor_failed" }
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $doctor -HeartbeatRefresh $heartbeat -ResultSummary "MATLAB doctor did not pass; no live success task was claimed."
  }

  $claim = Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -Body @{ worker_id = $WorkerId }
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    $preview.rejected_reason = "claim_failed"
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -Doctor $doctor -HeartbeatRefresh $heartbeat -ResultSummary "Task claim failed before MATLAB runner invocation."
  }

  $start = Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -Body @{ worker_id = $WorkerId }
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    $evidence = New-FailureEvidence -Category "start_failed" -Summary "Task start failed after claim; MATLAB was not invoked."
    Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body (Get-FinishBody -Evidence $evidence) | Out-Null
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionFailed $true -Evidence $evidence -Doctor $doctor -HeartbeatRefresh $heartbeat -FinalTaskState "failed" -ResultSummary "Task start failed after claim; fail was attempted."
  }

  $runner = Invoke-MatlabRunner -RunnerCommand "apply" -WithConfirm
  $evidence = $runner.evidence
  if (-not $evidence) {
    $evidence = New-FailureEvidence -Category "matlab_runner_no_evidence" -Summary "MATLAB runner returned no evidence."
  }
  $successEvidence = Test-SuccessEvidencePassed $evidence
  $finishBody = Get-FinishBody -Evidence $evidence

  if ($runner.ok -eq $true -and $successEvidence) {
    $complete = Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -Body $finishBody
    if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
      Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
      return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -Doctor $doctor -HeartbeatRefresh $heartbeat -FinalTaskState "failed" -ResultSummary "MATLAB evidence passed but task completion failed; fail was attempted."
    }
    $finalTask = Get-TaskViewById -RequestedTaskId $TaskId
    return New-RunRecord -Mode apply -Ok $true -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionCompleted $true -Evidence $evidence -Doctor $doctor -HeartbeatRefresh $heartbeat -FinalTaskState ([string]$finalTask.status) -ResultSummary ([string]$evidence.result_summary)
  }

  Invoke-SuccessApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
  $failedTask = Get-TaskViewById -RequestedTaskId $TaskId
  New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -Doctor $doctor -HeartbeatRefresh $heartbeat -FinalTaskState ([string]$failedTask.status) -ResultSummary ([string]$evidence.result_summary)
}

function Get-SuccessStatus {
  $version = Invoke-SuccessApi -Method GET -Path "/v1/version"
  $worker = Invoke-SuccessApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-SuccessApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $doctor = Invoke-MatlabDoctor -DoctorCommand "status"
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_success_status.v1"
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
    do_not_reuse_task_ids = @($DoNotReuseTaskIds)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    task_status = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { [string]$task.body.task.status } else { "missing" }
    matlab_detected = [bool]$doctor.matlab_detected
    doctor_fixed_script_visible = [bool]$doctor.fixed_script_visible
    doctor_precondition_passed = Test-DoctorPassed $doctor
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

function Get-SuccessReport {
  $worker = Invoke-SuccessApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-SuccessApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $taskBody = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { $task.body.task } else { $null }
  $evidenceSummary = if ($taskBody -and $taskBody.result) { $taskBody.result.evidence_summary } else { $null }
  [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_success_report.v1"
    ok = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    worker_id = $WorkerId
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    task_id = $TaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskIds)
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
  $result = Get-SuccessStatus
} elseif ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_matlab_golden_success_safe_summary.v1"
    ok = $true
    worker_id = $WorkerId
    task_id = $TaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskIds)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    next_safe_action = "doctor_preview_then_exact_confirm_doctor_apply_then_create_and_run_exact_success_task_if_doctor_passes"
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
      fallback_supported = $false
      run_mode = "not_available"
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
      matlab_exit_code = $null
      failure_category = "missing_exact_confirmation"
      failure_summary = "Exact confirmation is required before MATLAB startup diagnostic apply."
      recommended_next_action = "rerun_with_exact_doctor_confirmation"
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
    schema = "skybridge.live_matlab_golden_success_apply_run.v1"
    ok = $false
    runner_result = Invoke-RunApply
    report = $null
    task_id = $TaskId
    worker_id = $WorkerId
    token_printed = $false
  }
  $result.ok = [bool]$result.runner_result.ok
  $result.report = Get-SuccessReport
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
  $result = Get-SuccessReport
}

if ($Json) {
  $result | ConvertTo-Json -Depth 32
} else {
  $result | Format-List
}
