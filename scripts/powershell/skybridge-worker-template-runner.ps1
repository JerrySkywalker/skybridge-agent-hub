param(
  [ValidateSet("status", "preview", "apply-one", "fixture-seed-safe-task", "fixture-preview", "fixture-apply-one", "safe-summary")]
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
$SupportedTemplateId = "safe-local-smoke.v1"
$SupportedRunnerId = "safe-local-smoke-runner.v1"
$SupportedEvidenceSchemaId = "skybridge.local_smoke_evidence.v1"
$SupportedRequiredCapabilities = @("powershell", "node", "pnpm")
$SupportedAllowedPaths = @("scripts/powershell/smoke-worker-template-runner-preview.ps1", "tests/fixtures/worker-template-runner")
$SupportedBlockedPaths = @("production", "deploy", "server-root", ".env", "secrets", ".git", "GitHub settings")
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
    supported_template_ids = @($SupportedTemplateId)
    supported_runner_ids = @($SupportedRunnerId)
    confirmation_required = $true
    confirmation_text_required = $ConfirmationPhrase
    max_tasks = 1
    preview_default = $true
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
    supported_template_ids = @($SupportedTemplateId)
    supported_runner_ids = @($SupportedRunnerId)
    next_safe_action = "preview_then_exact_confirm_apply_one_or_hold"
    token_printed = $false
  }
} elseif ($Command -eq "fixture-seed-safe-task") {
  $result = Invoke-FixtureSeedSafeTask
} elseif ($Command -eq "fixture-preview") {
  $result = New-Preview
} elseif ($Command -eq "fixture-apply-one") {
  $result = Invoke-ApplyOne
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
