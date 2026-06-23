param(
  [ValidateSet(
    "status",
    "preview",
    "apply-one",
    "preview-live-one",
    "apply-live-one",
    "create-live-safe-task-preview",
    "create-live-safe-task-apply",
    "fixture-seed-safe-task",
    "fixture-preview",
    "fixture-apply-one",
    "safe-summary"
  )]
  [string]$Command = "preview",
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$TokenFile = "",
  [string]$WorkerId = "mg329-worker-template-runner",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "",
  [string]$TemplateId = "",
  [int]$MaxTasks = 1,
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$ConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_SAFE_TEMPLATE_TASK_ONLY"
$LiveConfirmationPhrase = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"
$LiveCreateConfirmationPhrase = "I_UNDERSTAND_CREATE_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"
$LivePilotTaskId = "live-safe-template-task-332-001"
$LiveEvidenceSchemaId = "skybridge.live_safe_template_task_evidence.v1"
$SupportedTemplateId = "safe-local-smoke.v1"
$SupportedRunnerId = "safe-local-smoke-runner.v1"
$SupportedEvidenceSchemaId = "skybridge.local_smoke_evidence.v1"
$SupportedRequiredCapabilities = @("powershell", "node", "pnpm")
$SupportedAllowedPaths = @("scripts/powershell/smoke-worker-template-runner-preview.ps1", "tests/fixtures/worker-template-runner")
$SupportedBlockedPaths = @("production", "deploy", "server-root", ".env", "secrets", ".git", "GitHub settings")
$LiveRequiredCapabilities = @("windows", "powershell", "node")
$LiveAllowedPaths = @(".agent/tmp/**")
$LiveBlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")
$RejectedTemplateIds = @(
  "matlab-parameter-sweep.v1",
  "matlab-result-analysis.v1",
  "codex-analysis-report.v1",
  "software-docs-task.v1"
)

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

function Get-AuthHeaders {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) {
    if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
      throw "TokenFile not found."
    }
    $token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $headers["Authorization"] = "Bearer $token"
    }
  }
  $headers
}

function Invoke-RunnerApi {
  param(
    [ValidateSet("GET", "POST")]
    [string]$Method,
    [string]$Path,
    $Body = $null
  )
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
  [pscustomobject]@{
    status_code = [int]$response.StatusCode
    body = $body
  }
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
  return [bool]($Text -match "(?i)\b(production|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|cookie|authorization|bearer|raw command|cmd\.exe|powershell -|pwsh -|bash -|matlab|codex|unbounded)\b")
}

function Get-ProjectView {
  $response = Invoke-RunnerApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.project }
  return $null
}

function Get-TaskViewById {
  param([string]$RequestedTaskId)
  if ([string]::IsNullOrWhiteSpace($RequestedTaskId)) { return $null }
  $response = Invoke-RunnerApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($RequestedTaskId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.task }
  return $null
}

function Test-TaskHasPilotMetadata {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  return (
    [string](Get-PropertyValue $metadata "adapter") -eq "mg332-live-safe-task-pilot" -and
    [string](Get-PropertyValue $metadata "reason") -eq "mg332_one_live_safe_template_task" -and
    [string](Get-PropertyValue $metadata "source_run_id") -eq "mega-goal-332-live-safe-task-pilot" -and
    [string](Get-PropertyValue $metadata "template_id") -eq $SupportedTemplateId -and
    [string](Get-PropertyValue $metadata "runner_id") -eq $SupportedRunnerId
  )
}

function Get-TaskTemplateId {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  $fromMetadata = [string](Get-PropertyValue $metadata "template_id")
  if (-not [string]::IsNullOrWhiteSpace($fromMetadata)) { return $fromMetadata }
  $taskType = [string](Get-PropertyValue $Task "task_type")
  $capabilities = @(ConvertTo-Array (Get-PropertyValue $Task "required_capabilities") | ForEach-Object { [string]$_ })
  if (($taskType -eq "local-validation" -or $taskType -eq "safe-local-smoke") -and (Test-ContainsAll $capabilities $SupportedRequiredCapabilities)) {
    return $SupportedTemplateId
  }
  if ($taskType -eq "docs") { return "software-docs-task.v1" }
  return ""
}

function Get-TaskRunnerId {
  param($Task, [string]$TemplateId)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  $fromMetadata = [string](Get-PropertyValue $metadata "runner_id")
  if (-not [string]::IsNullOrWhiteSpace($fromMetadata)) { return $fromMetadata }
  if ($TemplateId -eq $SupportedTemplateId) { return $SupportedRunnerId }
  if ($TemplateId -eq "software-docs-task.v1") { return "software-docs-task-runner.v1" }
  if ($TemplateId -eq "codex-analysis-report.v1") { return "codex-analysis-report-runner.v1" }
  if ($TemplateId -eq "matlab-parameter-sweep.v1") { return "matlab-parameter-sweep-runner.v1" }
  if ($TemplateId -eq "matlab-result-analysis.v1") { return "matlab-result-analysis-runner.v1" }
  return ""
}

function New-RunnerRecord {
  param(
    [ValidateSet("preview", "apply")]
    [string]$Mode = "preview",
    [bool]$Ok = $false,
    $Task = $null,
    [string]$TemplateId = "",
    [string]$RunnerId = "",
    [bool]$Selected = $false,
    [bool]$Eligible = $false,
    [string]$RejectedReason = "",
    [bool]$ClaimCreated = $false,
    [bool]$ExecutionStarted = $false,
    [bool]$ExecutionCompleted = $false,
    [bool]$ExecutionFailed = $false,
    [bool]$EvidencePresent = $false,
    [bool]$AllowedPathsChecked = $false,
    [bool]$BlockedPathsChecked = $false,
    [string[]]$ChangedFiles = @(),
    [string]$ValidationStatus = "not_run",
    [string]$ResultSummary = "",
    $RejectedTasks = @()
  )
  [pscustomobject]@{
    schema = if ($Mode -eq "apply") { "skybridge.worker_template_runner_result.v1" } else { "skybridge.worker_template_runner_preview.v1" }
    ok = $Ok
    mode = $Mode
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = if ($Task) { [string]$Task.task_id } else { $null }
    template_id = if ($TemplateId) { $TemplateId } else { $null }
    runner_id = if ($RunnerId) { $RunnerId } else { $null }
    selected = $Selected
    eligible = $Eligible
    rejected_reason = $RejectedReason
    claim_created = $ClaimCreated
    execution_started = $ExecutionStarted
    execution_completed = $ExecutionCompleted
    execution_failed = $ExecutionFailed
    evidence_present = $EvidencePresent
    allowed_paths_checked = $AllowedPathsChecked
    blocked_paths_checked = $BlockedPathsChecked
    changed_files = @($ChangedFiles)
    validation_status = $ValidationStatus
    result_summary = $ResultSummary
    rejected_tasks = @($RejectedTasks)
    pr_created = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function New-LiveRunnerRecord {
  param(
    [ValidateSet("preview", "apply")]
    [string]$Mode = "preview",
    [bool]$Ok = $false,
    $Task = $null,
    [bool]$Selected = $false,
    [bool]$Eligible = $false,
    [string]$RejectedReason = "",
    [bool]$ClaimCreated = $false,
    [bool]$ExecutionStarted = $false,
    [bool]$ExecutionCompleted = $false,
    [bool]$ExecutionFailed = $false,
    [bool]$EvidencePresent = $false,
    [bool]$AllowedPathsChecked = $false,
    [bool]$BlockedPathsChecked = $false,
    [string[]]$ChangedFiles = @(),
    [string]$ValidationStatus = "not_run",
    [string]$ResultSummary = "",
    [string]$CloudWorkerStatus = "unknown",
    [string]$FinalTaskState = "",
    $Evidence = $null
  )
  [pscustomobject]@{
    schema = if ($Mode -eq "apply") { "skybridge.worker_template_runner_result.v1" } else { "skybridge.worker_template_runner_preview.v1" }
    ok = $Ok
    mode = $Mode
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = if ($Task) { [string]$Task.task_id } elseif (-not [string]::IsNullOrWhiteSpace($TaskId)) { $TaskId } else { $LivePilotTaskId }
    expected_task_id = $LivePilotTaskId
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    evidence_schema = $LiveEvidenceSchemaId
    selected = $Selected
    eligible = $Eligible
    selected_task_count = if ($Selected) { 1 } else { 0 }
    rejected_reason = $RejectedReason
    claim_created = $ClaimCreated
    task_claimed_count = if ($ClaimCreated) { 1 } else { 0 }
    old_task_claimed = $false
    execution_started = $ExecutionStarted
    execution_completed = $ExecutionCompleted
    execution_failed = $ExecutionFailed
    evidence_present = $EvidencePresent
    evidence = $Evidence
    allowed_paths_checked = $AllowedPathsChecked
    blocked_paths_checked = $BlockedPathsChecked
    changed_files = @($ChangedFiles)
    validation_status = $ValidationStatus
    result_summary = $ResultSummary
    final_task_state = $FinalTaskState
    cloud_worker_status = $CloudWorkerStatus
    pr_created = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Get-WorkerView {
  $response = Invoke-RunnerApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.worker }
  return $null
}

function Test-RunnerEligibility {
  param($Task, $Worker)
  $template = Get-TaskTemplateId $Task
  $runner = Get-TaskRunnerId $Task $template
  $reasons = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($TaskId) -and [string]$Task.task_id -ne $TaskId) { $reasons.Add("task_id_filter_mismatch") | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($TemplateId) -and $template -ne $TemplateId) { $reasons.Add("template_id_filter_mismatch") | Out-Null }
  if ([string]$Task.status -ne "queued") { $reasons.Add("task_not_queued") | Out-Null }
  if ([string]$Task.risk -ne "low") { $reasons.Add("risk_not_low") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($template)) { $reasons.Add("unknown_template_id") | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($template) -and $template -ne $SupportedTemplateId -and $RejectedTemplateIds -notcontains $template) {
    $reasons.Add("unknown_template_id") | Out-Null
  }
  if ($RejectedTemplateIds -contains $template) {
    if ($template -like "matlab-*") { $reasons.Add("matlab_template_rejected_mg329") | Out-Null }
    elseif ($template -like "codex-*" -or $template -eq "software-docs-task.v1") { $reasons.Add("codex_or_docs_runner_deferred_mg329") | Out-Null }
    else { $reasons.Add("template_not_supported_mg329") | Out-Null }
  }
  if ($template -ne $SupportedTemplateId) { $reasons.Add("template_not_supported_mg329") | Out-Null }
  if ($runner -ne $SupportedRunnerId) { $reasons.Add("runner_not_supported_mg329") | Out-Null }
  if ($Task.lease -and [string]$Task.lease.lease_status -eq "active") { $reasons.Add("active_lease_exists") | Out-Null }
  if ($Task.claim) { $reasons.Add("existing_claim_residue") | Out-Null }
  if (-not $Worker) {
    $reasons.Add("worker_not_registered_or_offline") | Out-Null
  } else {
    if ($Worker.status -ne "online") { $reasons.Add("worker_not_online") | Out-Null }
    if ($Worker.enabled -ne $true) { $reasons.Add("worker_disabled") | Out-Null }
    $workerCapabilities = @(ConvertTo-Array $Worker.capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $workerCapabilities $SupportedRequiredCapabilities)) { $reasons.Add("worker_missing_required_capabilities") | Out-Null }
  }

  $requiredCapabilities = @(ConvertTo-Array $Task.required_capabilities | ForEach-Object { [string]$_ })
  if (-not (Test-ContainsAll $requiredCapabilities $SupportedRequiredCapabilities)) { $reasons.Add("task_missing_supported_capabilities") | Out-Null }
  if ($requiredCapabilities -contains "codex") { $reasons.Add("codex_capability_rejected_mg329") | Out-Null }
  if ($requiredCapabilities -contains "matlab") { $reasons.Add("matlab_capability_rejected_mg329") | Out-Null }

  $allowedPaths = @(ConvertTo-Array $Task.allowed_paths | ForEach-Object { [string]$_ })
  $blockedPaths = @(ConvertTo-Array $Task.blocked_paths | ForEach-Object { [string]$_ })
  $allowedOk = $allowedPaths.Count -gt 0 -and (Test-Subset $allowedPaths $SupportedAllowedPaths)
  $blockedOk = Test-ContainsAll $blockedPaths $SupportedBlockedPaths
  if (-not $allowedOk) { $reasons.Add("allowed_paths_outside_template_policy") | Out-Null }
  if (-not $blockedOk) { $reasons.Add("blocked_paths_missing_template_policy") | Out-Null }

  $text = @(
    [string]$Task.title,
    [string]$Task.body,
    [string]$Task.prompt_summary,
    ($allowedPaths -join " ")
  ) -join " "
  if (Test-UnsafeText $text) { $reasons.Add("unsafe_path_or_text_detected") | Out-Null }

  [pscustomobject]@{
    task = $Task
    template_id = $template
    runner_id = $runner
    eligible = ($reasons.Count -eq 0)
    rejected_reason = (($reasons | Select-Object -Unique) -join ";")
    allowed_paths_checked = $allowedOk
    blocked_paths_checked = $blockedOk
  }
}

function Test-LiveRunnerEligibility {
  param($Task, $Worker)
  $reasons = New-Object System.Collections.Generic.List[string]
  $template = Get-TaskTemplateId $Task
  $runner = Get-TaskRunnerId $Task $template

  if ([string]::IsNullOrWhiteSpace($WorkerId) -or $WorkerId -eq "mg329-worker-template-runner") { $reasons.Add("worker_id_must_be_explicit_for_live") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($ProjectId)) { $reasons.Add("project_id_required") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($TaskId)) { $reasons.Add("task_id_required") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($TemplateId)) { $reasons.Add("template_id_required") | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($TaskId) -and $TaskId -ne $LivePilotTaskId) { $reasons.Add("unexpected_live_task_id") | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($TemplateId) -and $TemplateId -ne $SupportedTemplateId) { $reasons.Add("template_not_supported_mg332_live") | Out-Null }

  if ($Task) {
    if ([string]$Task.task_id -ne $LivePilotTaskId) { $reasons.Add("selected_task_id_mismatch") | Out-Null }
    if ([string]$Task.project_id -ne $ProjectId) { $reasons.Add("project_id_mismatch") | Out-Null }
    if ([string]$Task.status -ne "queued") {
      if ([string]$Task.status -in @("completed", "cancelled", "blocked")) { $reasons.Add("target_task_terminal_or_blocked") | Out-Null }
      else { $reasons.Add("target_task_not_queued") | Out-Null }
    }
    if ([string]$Task.risk -ne "low") { $reasons.Add("risk_not_low") | Out-Null }
    if ($template -ne $SupportedTemplateId) { $reasons.Add("template_not_supported_mg332_live") | Out-Null }
    if ($runner -ne $SupportedRunnerId) { $reasons.Add("runner_not_supported_mg332_live") | Out-Null }
    if ($Task.lease -and [string]$Task.lease.lease_status -eq "active") { $reasons.Add("active_lease_exists") | Out-Null }
    if ($Task.claim) { $reasons.Add("existing_claim_residue") | Out-Null }
    if (-not (Test-TaskHasPilotMetadata $Task)) { $reasons.Add("task_not_created_by_mg332_pilot") | Out-Null }

    $requiredCapabilities = @(ConvertTo-Array $Task.required_capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $requiredCapabilities $LiveRequiredCapabilities)) { $reasons.Add("task_missing_live_required_capabilities") | Out-Null }
    if ($requiredCapabilities -contains "codex") { $reasons.Add("codex_capability_rejected_mg332") | Out-Null }
    if ($requiredCapabilities -contains "matlab") { $reasons.Add("matlab_capability_rejected_mg332") | Out-Null }

    $allowedPaths = @(ConvertTo-Array $Task.allowed_paths | ForEach-Object { [string]$_ })
    $blockedPaths = @(ConvertTo-Array $Task.blocked_paths | ForEach-Object { [string]$_ })
    $allowedOk = $allowedPaths.Count -gt 0 -and (Test-Subset $allowedPaths $LiveAllowedPaths)
    $blockedOk = Test-ContainsAll $blockedPaths $LiveBlockedPaths
    if (-not $allowedOk) { $reasons.Add("allowed_paths_outside_live_policy") | Out-Null }
    if (-not $blockedOk) { $reasons.Add("blocked_paths_missing_live_policy") | Out-Null }

    $text = @(
      [string]$Task.title,
      [string]$Task.body,
      [string]$Task.prompt_summary,
      ($allowedPaths -join " ")
    ) -join " "
    if (Test-UnsafeText $text) { $reasons.Add("unsafe_path_or_text_detected") | Out-Null }
  } else {
    $reasons.Add("target_task_not_found") | Out-Null
    $allowedOk = $false
    $blockedOk = $false
  }

  if (-not $Worker) {
    $reasons.Add("worker_not_registered_or_offline") | Out-Null
    $workerStatus = "unknown"
  } else {
    $workerStatus = [string]$Worker.status
    if ($Worker.status -ne "online") { $reasons.Add("worker_not_online") | Out-Null }
    if ($Worker.enabled -ne $true) { $reasons.Add("worker_disabled") | Out-Null }
    $workerCapabilities = @(ConvertTo-Array $Worker.capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $workerCapabilities $LiveRequiredCapabilities)) { $reasons.Add("worker_missing_live_required_capabilities") | Out-Null }
  }

  [pscustomobject]@{
    task = $Task
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    eligible = ($reasons.Count -eq 0)
    rejected_reason = (($reasons | Select-Object -Unique) -join ";")
    allowed_paths_checked = $allowedOk
    blocked_paths_checked = $blockedOk
    cloud_worker_status = $workerStatus
  }
}

function New-LivePreview {
  if ($MaxTasks -gt 1) {
    return New-LiveRunnerRecord -Mode preview -RejectedReason "max_tasks_exceeds_mg332_live_limit" -ResultSummary "MG332 live apply is hard-limited to one exact task."
  }
  $worker = Get-WorkerView
  $task = Get-TaskViewById -RequestedTaskId $TaskId
  $candidate = Test-LiveRunnerEligibility $task $worker
  if (-not $candidate.eligible) {
    return New-LiveRunnerRecord `
      -Mode preview `
      -Task $task `
      -RejectedReason $candidate.rejected_reason `
      -AllowedPathsChecked $candidate.allowed_paths_checked `
      -BlockedPathsChecked $candidate.blocked_paths_checked `
      -CloudWorkerStatus $candidate.cloud_worker_status `
      -ValidationStatus "blocked" `
      -ResultSummary "MG332 live safe task pilot did not meet exact-task preconditions."
  }
  New-LiveRunnerRecord `
    -Mode preview `
    -Ok $true `
    -Task $task `
    -Selected $true `
    -Eligible $true `
    -AllowedPathsChecked $candidate.allowed_paths_checked `
    -BlockedPathsChecked $candidate.blocked_paths_checked `
    -CloudWorkerStatus $candidate.cloud_worker_status `
    -ValidationStatus "preview_only" `
    -FinalTaskState ([string]$task.status) `
    -ResultSummary "One exact MG332 live safe-local-smoke task selected; apply-live-one still requires exact confirmation."
}

function New-LiveSafeTemplateEvidence {
  param($Preview, [string]$StartedAt)
  $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
  $evidenceDir = Join-Path $repoRoot ".agent\tmp\live-safe-template-task-332\$($Preview.task_id)"
  New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
  $evidencePath = Join-Path $evidenceDir "evidence.json"
  $relativeEvidencePath = ".agent/tmp/live-safe-template-task-332/$($Preview.task_id)/evidence.json"
  $completedAt = (Get-Date).ToUniversalTime().ToString("o")
  $evidence = [pscustomobject]@{
    schema = $LiveEvidenceSchemaId
    task_id = $Preview.task_id
    worker_id = $WorkerId
    project_id = $ProjectId
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    started_at = $StartedAt
    completed_at = $completedAt
    failed_at = $null
    validation_status = "passed"
    changed_files = @($relativeEvidencePath)
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    old_task_claimed = $false
    task_claimed_count = 1
    result_summary = "MG332 live safe-local-smoke runner completed one exact pilot task with sanitized evidence only."
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    raw_logs_included = $false
    token_printed = $false
  }
  $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
  $evidence
}

function New-LiveFailureEvidenceSummary {
  param([string]$Reason)
  [pscustomobject]@{
    summary = "MG332 live safe-local-smoke runner failed safely: $Reason"
    task_id = $TaskId
    changed_files = @()
    validation_status = "failed"
    risk_status = "low_live_safe_template"
    created_at = (Get-Date).ToUniversalTime().ToString("o")
  }
}

function Invoke-LiveFailTask {
  param([string]$Reason)
  try {
    Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body @{
      worker_id = $WorkerId
      summary = "MG332 live safe-local-smoke runner failed safely."
      error_summary = $Reason
      evidence_summary = New-LiveFailureEvidenceSummary -Reason $Reason
    } | Out-Null
  } catch {
    # Best-effort failure marking only; the caller reports the original failure.
  }
}

function Invoke-LiveApplyOne {
  if ($MaxTasks -gt 1) {
    return New-LiveRunnerRecord -Mode apply -RejectedReason "max_tasks_exceeds_mg332_live_limit" -ResultSummary "MG332 live apply is hard-limited to one exact task."
  }
  $preview = New-LivePreview
  if (-not $preview.ok) {
    return New-LiveRunnerRecord `
      -Mode apply `
      -Task (Get-TaskViewById -RequestedTaskId $TaskId) `
      -RejectedReason $preview.rejected_reason `
      -AllowedPathsChecked $preview.allowed_paths_checked `
      -BlockedPathsChecked $preview.blocked_paths_checked `
      -CloudWorkerStatus $preview.cloud_worker_status `
      -ValidationStatus "blocked" `
      -ResultSummary $preview.result_summary
  }
  if (-not $Confirm -or $ConfirmationText -ne $LiveConfirmationPhrase) {
    return New-LiveRunnerRecord `
      -Mode apply `
      -Task (Get-TaskViewById -RequestedTaskId $TaskId) `
      -Selected $true `
      -Eligible $true `
      -RejectedReason "missing_exact_confirmation" `
      -AllowedPathsChecked $true `
      -BlockedPathsChecked $true `
      -CloudWorkerStatus $preview.cloud_worker_status `
      -ValidationStatus "blocked" `
      -ResultSummary "Exact MG332 live confirmation is required before claiming one live safe template task."
  }

  $claim = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/claim" -Body @{ worker_id = $WorkerId }
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    return New-LiveRunnerRecord -Mode apply -Task (Get-TaskViewById -RequestedTaskId $TaskId) -Selected $true -Eligible $true -RejectedReason "claim_failed" -CloudWorkerStatus $preview.cloud_worker_status -ValidationStatus "failed" -ResultSummary "Live task claim failed before execution."
  }

  $startedAt = (Get-Date).ToUniversalTime().ToString("o")
  $start = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/start" -Body @{ worker_id = $WorkerId }
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    Invoke-LiveFailTask -Reason "start_failed"
    return New-LiveRunnerRecord -Mode apply -Task (Get-TaskViewById -RequestedTaskId $TaskId) -Selected $true -Eligible $true -ClaimCreated $true -ExecutionFailed $true -RejectedReason "start_failed" -CloudWorkerStatus $preview.cloud_worker_status -ValidationStatus "failed" -ResultSummary "Live task start failed after claim; fail was attempted."
  }

  $evidence = New-LiveSafeTemplateEvidence -Preview $preview -StartedAt $startedAt
  $complete = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/complete" -Body @{
    worker_id = $WorkerId
    summary = $evidence.result_summary
    evidence_summary = @{
      task_id = $preview.task_id
      changed_files = @($evidence.changed_files)
      validation_status = $evidence.validation_status
      risk_status = "low_live_safe_template"
      summary = $evidence.result_summary
      created_at = $evidence.completed_at
    }
  }
  if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
    Invoke-LiveFailTask -Reason "complete_failed"
    return New-LiveRunnerRecord -Mode apply -Task (Get-TaskViewById -RequestedTaskId $TaskId) -Selected $true -Eligible $true -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -EvidencePresent $true -RejectedReason "complete_failed" -CloudWorkerStatus $preview.cloud_worker_status -ChangedFiles @($evidence.changed_files) -ValidationStatus "failed" -ResultSummary "Live task completion failed after evidence generation; fail was attempted." -Evidence $evidence
  }
  $finalTask = Get-TaskViewById -RequestedTaskId $TaskId
  New-LiveRunnerRecord `
    -Mode apply `
    -Ok $true `
    -Task $finalTask `
    -Selected $true `
    -Eligible $true `
    -ClaimCreated $true `
    -ExecutionStarted $true `
    -ExecutionCompleted $true `
    -EvidencePresent $true `
    -AllowedPathsChecked $true `
    -BlockedPathsChecked $true `
    -ChangedFiles @($evidence.changed_files) `
    -ValidationStatus $evidence.validation_status `
    -ResultSummary $evidence.result_summary `
    -CloudWorkerStatus $preview.cloud_worker_status `
    -FinalTaskState ([string]$finalTask.status) `
    -Evidence $evidence
}

function New-LiveSafeTaskPayload {
  param([string]$RequestedTaskId)
  [pscustomobject]@{
    task_id = $RequestedTaskId
    project_id = $ProjectId
    title = "MG332 live safe template task"
    body = "Run the fixed MG332 safe-local-smoke runner only. No external tool runners, shell surface, loop, PR, project-control unpause, or remote infrastructure changes."
    prompt_summary = "MG332 deterministic live safe-local-smoke task. Safe summary only; raw prompt not persisted."
    risk = "low"
    source = "manual"
    task_type = "safe-local-smoke"
    allowed_paths = @($LiveAllowedPaths)
    blocked_paths = @($LiveBlockedPaths)
    validation = @(
      "fixed safe-local-smoke runner completed",
      "evidence summary present",
      "no files outside allowed_paths changed",
      "token_printed=false"
    )
    required_capabilities = @($LiveRequiredCapabilities)
    planner_metadata = @{
      adapter = "mg332-live-safe-task-pilot"
      decision = "continue"
      reason = "mg332_one_live_safe_template_task"
      task_type = "safe-local-smoke"
      template_id = $SupportedTemplateId
      runner_id = $SupportedRunnerId
      evidence_schema = @($LiveEvidenceSchemaId)
      allowed_paths = @($LiveAllowedPaths)
      blocked_paths = @($LiveBlockedPaths)
      validation = @(
        "fixed safe-local-smoke runner completed",
        "evidence summary present",
        "no files outside allowed_paths changed",
        "token_printed=false"
      )
      expected_files = @()
      expected_outputs = @(".agent/tmp/live-safe-template-task-332/**")
      stop_criteria_status = @("complete_exact_live_safe_template_task_then_stop")
      source_run_id = "mega-goal-332-live-safe-task-pilot"
      created_at = (Get-Date).ToUniversalTime().ToString("o")
      claim_enabled = $true
      execution_scope = "fixed_safe_local_smoke_only"
      codex_run_called = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      worker_loop_started = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
}

function Invoke-CreateLiveSafeTaskPreview {
  $targetTaskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { $LivePilotTaskId } else { $TaskId }
  $project = Get-ProjectView
  $existing = Get-TaskViewById -RequestedTaskId $targetTaskId
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($targetTaskId -ne $LivePilotTaskId) { $blockers.Add("unexpected_live_task_id") | Out-Null }
  if (-not $project) { $blockers.Add("project_not_found") | Out-Null }
  if ($existing -and -not (Test-TaskHasPilotMetadata $existing)) { $blockers.Add("existing_task_not_mg332_pilot") | Out-Null }
  if ($existing -and [string]$existing.status -ne "queued") { $blockers.Add("existing_task_not_queued") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_create_preview.v1"
    ok = ($blockers.Count -eq 0)
    mode = "preview"
    project_id = $ProjectId
    task_id = $targetTaskId
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    task_exists = [bool]$existing
    would_create_task = -not [bool]$existing -and $blockers.Count -eq 0
    task_created = $false
    blockers = @($blockers)
    allowed_paths = @($LiveAllowedPaths)
    blocked_paths = @($LiveBlockedPaths)
    required_capabilities = @($LiveRequiredCapabilities)
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Invoke-CreateLiveSafeTaskApply {
  $preview = Invoke-CreateLiveSafeTaskPreview
  if (-not $preview.ok) {
    return [pscustomobject]@{
      schema = "skybridge.live_safe_task_pilot_create_result.v1"
      ok = $false
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $SupportedTemplateId
      runner_id = $SupportedRunnerId
      task_created = $false
      review_reason = "create_preconditions_failed"
      blockers = @($preview.blockers)
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  if (-not $Confirm -or $ConfirmationText -ne $LiveCreateConfirmationPhrase) {
    return [pscustomobject]@{
      schema = "skybridge.live_safe_task_pilot_create_result.v1"
      ok = $false
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $SupportedTemplateId
      runner_id = $SupportedRunnerId
      task_created = $false
      review_reason = "missing_exact_confirmation"
      blockers = @("missing_exact_confirmation")
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  if ($preview.task_exists) {
    return [pscustomobject]@{
      schema = "skybridge.live_safe_task_pilot_create_result.v1"
      ok = $true
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $SupportedTemplateId
      runner_id = $SupportedRunnerId
      task_created = $false
      task_already_present = $true
      review_reason = "existing_mg332_queued_task_reused_without_requeue"
      blockers = @()
      claim_created = $false
      execution_started = $false
      worker_loop_started = $false
      codex_run_called = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
  $body = New-LiveSafeTaskPayload -RequestedTaskId $preview.task_id
  $response = Invoke-RunnerApi -Method POST -Path "/v1/tasks" -Body $body
  $created = ($response.status_code -ge 200 -and $response.status_code -lt 300)
  [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_create_result.v1"
    ok = $created
    mode = "apply"
    project_id = $ProjectId
    task_id = $preview.task_id
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    task_created = $created
    task_status = if ($created) { [string]$response.body.task.status } else { "unknown" }
    review_reason = if ($created) { "exact_confirmation_received_created_one_live_safe_task" } else { "task_create_failed" }
    blockers = if ($created) { @() } else { @("task_create_failed") }
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function New-Preview {
  $worker = Get-WorkerView
  $tasksResponse = Invoke-RunnerApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))"
  if ($tasksResponse.status_code -lt 200 -or $tasksResponse.status_code -ge 300) {
    return New-RunnerRecord -Mode preview -RejectedReason "task_list_unavailable" -ResultSummary "Unable to read task list."
  }
  $evaluated = @($tasksResponse.body.tasks | ForEach-Object { Test-RunnerEligibility $_ $worker })
  $selected = @($evaluated | Where-Object { $_.eligible } | Select-Object -First 1)
  $rejected = @($evaluated | Where-Object { -not $_.eligible } | ForEach-Object {
    [pscustomobject]@{
      task_id = [string]$_.task.task_id
      template_id = $_.template_id
      runner_id = $_.runner_id
      rejected_reason = $_.rejected_reason
    }
  })
  if ($selected.Count -eq 0) {
    return New-RunnerRecord `
      -Mode preview `
      -RejectedReason "no_eligible_template_task" `
      -ResultSummary "No eligible MG329 safe-local-smoke task selected." `
      -RejectedTasks $rejected
  }
  $candidate = $selected[0]
  New-RunnerRecord `
    -Mode preview `
    -Ok $true `
    -Task $candidate.task `
    -TemplateId $candidate.template_id `
    -RunnerId $candidate.runner_id `
    -Selected $true `
    -Eligible $true `
    -AllowedPathsChecked $candidate.allowed_paths_checked `
    -BlockedPathsChecked $candidate.blocked_paths_checked `
    -ValidationStatus "preview_only" `
    -ResultSummary "One eligible MG329 safe-local-smoke task selected; apply-one still requires exact confirmation." `
    -RejectedTasks $rejected
}

function New-TemplateRunnerEvidence {
  param($Preview)
  $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
  $evidenceDir = Join-Path $repoRoot ".agent\tmp\worker-template-runner\$($Preview.task_id)"
  New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
  $evidencePath = Join-Path $evidenceDir "evidence.json"
  $evidence = [pscustomobject]@{
    schema = "skybridge.template_runner_evidence.v1"
    ok = $true
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = $Preview.task_id
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    evidence_schema_id = $SupportedEvidenceSchemaId
    evidence_path = ".agent/tmp/worker-template-runner/$($Preview.task_id)/evidence.json"
    changed_files = @()
    validation_status = "passed"
    result_summary = "MG329 safe-local-smoke fixture runner completed without Codex, MATLAB, shell, PR, worker loop, or project-control unpause."
    pr_created = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    raw_logs_included = $false
    token_printed = $false
  }
  $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
  $evidence
}

function Invoke-ApplyOne {
  if ($MaxTasks -gt 1) {
    return New-RunnerRecord -Mode apply -RejectedReason "max_tasks_exceeds_mg329_limit" -ResultSummary "MG329 apply-one is hard-limited to one task."
  }
  $preview = New-Preview
  if (-not $preview.ok) {
    return New-RunnerRecord -Mode apply -RejectedReason $preview.rejected_reason -ResultSummary $preview.result_summary -RejectedTasks $preview.rejected_tasks
  }
  if (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
    return New-RunnerRecord `
      -Mode apply `
      -Task $preview `
      -TemplateId $preview.template_id `
      -RunnerId $preview.runner_id `
      -Selected $true `
      -Eligible $true `
      -AllowedPathsChecked $preview.allowed_paths_checked `
      -BlockedPathsChecked $preview.blocked_paths_checked `
      -RejectedReason "missing_exact_confirmation" `
      -ResultSummary "Exact confirmation is required before running one safe template task."
  }

  $claim = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/claim" -Body @{ worker_id = $WorkerId }
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    return New-RunnerRecord -Mode apply -Task $preview -TemplateId $preview.template_id -RunnerId $preview.runner_id -Selected $true -Eligible $true -RejectedReason "claim_failed" -ResultSummary "Task claim failed before execution."
  }

  $start = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/start" -Body @{ worker_id = $WorkerId }
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    return New-RunnerRecord -Mode apply -Task $preview -TemplateId $preview.template_id -RunnerId $preview.runner_id -Selected $true -Eligible $true -ClaimCreated $true -ExecutionFailed $true -RejectedReason "start_failed" -ResultSummary "Task start failed after claim."
  }

  $evidence = New-TemplateRunnerEvidence -Preview $preview
  $complete = Invoke-RunnerApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($preview.task_id))/complete" -Body @{
    worker_id = $WorkerId
    summary = $evidence.result_summary
    evidence_summary = @{
      task_id = $preview.task_id
      changed_files = @($evidence.changed_files)
      validation_status = $evidence.validation_status
      risk_status = "low_fixture_only"
      summary = $evidence.result_summary
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
  if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
    return New-RunnerRecord -Mode apply -Task $preview -TemplateId $preview.template_id -RunnerId $preview.runner_id -Selected $true -Eligible $true -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -EvidencePresent $true -RejectedReason "complete_failed" -ResultSummary "Task completion failed after fixture evidence generation."
  }

  New-RunnerRecord `
    -Mode apply `
    -Ok $true `
    -Task $preview `
    -TemplateId $preview.template_id `
    -RunnerId $preview.runner_id `
    -Selected $true `
    -Eligible $true `
    -ClaimCreated $true `
    -ExecutionStarted $true `
    -ExecutionCompleted $true `
    -EvidencePresent $true `
    -AllowedPathsChecked $true `
    -BlockedPathsChecked $true `
    -ChangedFiles @($evidence.changed_files) `
    -ValidationStatus $evidence.validation_status `
    -ResultSummary $evidence.result_summary
}

function Invoke-FixtureSeedSafeTask {
  Invoke-RunnerApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = "MG329 Worker Template Runner Fixture" } | Out-Null
  Invoke-RunnerApi -Method POST -Path "/v1/workers/register" -Body @{
    worker_id = $WorkerId
    name = "MG329 fixture worker"
    provider = "local-powershell"
    capabilities = @($SupportedRequiredCapabilities)
    labels = @("mg329-fixture", "safe-local-smoke")
    enabled = $true
  } | Out-Null
  Invoke-RunnerApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))/heartbeat" -Body @{ status_note = "mg329 fixture ready"; load = 0 } | Out-Null
  $taskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { "mg329-safe-local-smoke-fixture" } else { $TaskId }
  Invoke-RunnerApi -Method POST -Path "/v1/tasks" -Body @{
    task_id = $taskId
    project_id = $ProjectId
    title = "MG329 safe local smoke fixture"
    body = "Run the fixed MG329 safe local smoke fixture only."
    prompt_summary = "Fixed safe-local-smoke fixture. No raw prompt persistence."
    risk = "low"
    source = "manual"
    task_type = "local-validation"
    allowed_paths = @($SupportedAllowedPaths)
    blocked_paths = @($SupportedBlockedPaths)
    validation = @("Verify fixture evidence contract and disabled execution flags.")
    required_capabilities = @($SupportedRequiredCapabilities)
    planner_metadata = @{
      adapter = "mg329-worker-template-runner-fixture"
      decision = "continue"
      reason = "mg329_fixture_safe_local_smoke"
      task_type = "local-validation"
      template_id = $SupportedTemplateId
      runner_id = $SupportedRunnerId
      evidence_schema = @($SupportedEvidenceSchemaId)
      allowed_paths = @($SupportedAllowedPaths)
      blocked_paths = @($SupportedBlockedPaths)
      validation = @("Verify fixture evidence contract and disabled execution flags.")
      expected_files = @()
      expected_outputs = @(".agent/tmp/worker-template-runner/**")
      stop_criteria_status = @("complete_one_fixture_task_then_stop")
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  } | Out-Null
  [pscustomobject]@{
    schema = "skybridge.worker_template_runner_fixture_seed.v1"
    ok = $true
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = $taskId
    template_id = $SupportedTemplateId
    runner_id = $SupportedRunnerId
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.worker_template_runner_status.v1"
    ok = $true
    worker_id = $WorkerId
    project_id = $ProjectId
    live_pilot_task_id = $LivePilotTaskId
    supported_template_ids = @($SupportedTemplateId)
    supported_runner_ids = @($SupportedRunnerId)
    confirmation_required = $true
    confirmation_text_required = $ConfirmationPhrase
    live_confirmation_text_required = $LiveConfirmationPhrase
    live_create_confirmation_text_required = $LiveCreateConfirmationPhrase
    max_tasks = 1
    preview_default = $true
    live_exact_task_apply_supported = $true
    live_create_safe_task_supported = $true
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

if ($Command -eq "status") {
  $result = New-Status
} elseif ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.worker_template_runner_safe_summary.v1"
    ok = $true
    worker_id = $WorkerId
    project_id = $ProjectId
    live_pilot_task_id = $LivePilotTaskId
    supported_template_ids = @($SupportedTemplateId)
    supported_runner_ids = @($SupportedRunnerId)
    next_safe_action = "preview_then_exact_confirm_apply_one_or_live_exact_task_or_hold"
    token_printed = $false
  }
} elseif ($Command -eq "fixture-seed-safe-task") {
  $result = Invoke-FixtureSeedSafeTask
} elseif ($Command -eq "fixture-preview") {
  $result = New-Preview
} elseif ($Command -eq "fixture-apply-one") {
  $result = Invoke-ApplyOne
} elseif ($Command -eq "create-live-safe-task-preview") {
  $result = Invoke-CreateLiveSafeTaskPreview
} elseif ($Command -eq "create-live-safe-task-apply") {
  $result = Invoke-CreateLiveSafeTaskApply
} elseif ($Command -eq "preview-live-one") {
  $result = New-LivePreview
} elseif ($Command -eq "apply-live-one") {
  $result = Invoke-LiveApplyOne
} elseif ($Command -eq "apply-one") {
  $result = Invoke-ApplyOne
} else {
  $result = New-Preview
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
