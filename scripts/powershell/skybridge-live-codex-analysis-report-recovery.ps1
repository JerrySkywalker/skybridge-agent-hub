param(
  [ValidateSet("status", "preview-create", "apply-create", "preview-run", "apply-run", "report", "safe-summary")]
  [string]$Command = "status",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "live-codex-analysis-report-task-338-001",
  [string]$TemplateId = "codex-analysis-report.v1",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$TargetTaskId = "live-codex-analysis-report-task-338-001"
$DoNotReuseTaskId = "live-codex-analysis-report-task-337-001"
$WorkerIdTarget = "jerry-win-local-01"
$TemplateIdTarget = "codex-analysis-report.v1"
$RunnerIdTarget = "codex-analysis-report-runner.v1"
$EvidenceSchemaId = "skybridge.codex_analysis_report_evidence.v1"
$CreateConfirmationPhrase = "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY"
$RunConfirmationPhrase = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY"
$RunnerConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY"
$HeartbeatConfirmationPhrase = "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM"
$InputManifest = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json"
$InputSummary = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json"
$InputMetrics = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv"
$OutputDir = ".agent/tmp/codex-analysis-report/$TargetTaskId"
$OutputReport = "$OutputDir/report.md"
$RequiredCapabilities = @("windows", "powershell", "codex")
$AllowedPaths = @($InputManifest, $InputSummary, $InputMetrics, ".agent/tmp/codex-analysis-report/**")
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
  [bool]($positiveText -match "(?i)\b(production|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|cookie|authorization|bearer|raw command|cmd\.exe|powershell -|pwsh -|bash -|matlab -batch|run matlab|arbitrary prompt|create pr|pull request|auto-merge|unbounded|environment dump)\b")
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

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$HomeRoot = [Environment]::GetFolderPath("UserProfile")
$SkyBridgeConfigPath = Join-Path $HomeRoot ".skybridge\skybridge.env.ps1"
$WorkerConfigPath = Join-Path $HomeRoot ".skybridge\worker.env.ps1"

if ([string]::IsNullOrWhiteSpace($ApiBase)) {
  $ApiBase = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) { $env:SKYBRIDGE_API_BASE } else { Get-ConfigValueFromFile -Path $SkyBridgeConfigPath -Name "SKYBRIDGE_API_BASE" }
}
if ([string]::IsNullOrWhiteSpace($TokenFile)) {
  $TokenFile = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE)) { $env:SKYBRIDGE_WORKER_TOKEN_FILE } else { Get-ConfigValueFromFile -Path $WorkerConfigPath -Name "SKYBRIDGE_WORKER_TOKEN_FILE" }
}
if ([string]::IsNullOrWhiteSpace($TokenFile)) { $TokenFile = Join-Path $HomeRoot ".skybridge\worker-token.txt" }
$TokenFile = Resolve-HomePathValue $TokenFile
if ([string]::IsNullOrWhiteSpace($WorkerId)) {
  $WorkerId = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_ID)) { $env:SKYBRIDGE_WORKER_ID } else { Get-ConfigValueFromFile -Path $WorkerConfigPath -Name "SKYBRIDGE_WORKER_ID" }
}
if ([string]::IsNullOrWhiteSpace($WorkerId)) { $WorkerId = $WorkerIdTarget }

function Get-AuthHeaders {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($TokenFile) -and (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
    $token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["Authorization"] = "Bearer $token" }
  }
  $headers
}

function Invoke-CodexReportApi {
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

function Invoke-Runner {
  param([string]$RunnerCommand, [switch]$WithConfirm)
  $runnerPath = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $runnerPath,
    "-Command",
    $RunnerCommand,
    "-TaskId",
    $TargetTaskId,
    "-WorkerId",
    $WorkerId,
    "-InputManifest",
    $InputManifest,
    "-InputSummary",
    $InputSummary,
    "-InputMetrics",
    $InputMetrics,
    "-OutputDir",
    $OutputDir,
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
  $response = Invoke-CodexReportApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.project }
  $null
}

function Get-WorkerView {
  $response = Invoke-CodexReportApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.worker }
  $null
}

function Get-TaskViewById {
  param([string]$RequestedTaskId)
  if ([string]::IsNullOrWhiteSpace($RequestedTaskId)) { return $null }
  $response = Invoke-CodexReportApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($RequestedTaskId))"
  if ($response.status_code -ge 200 -and $response.status_code -lt 300) { return $response.body.task }
  $null
}

function Test-TaskHasCodexReportMetadata {
  param($Task)
  $metadata = Get-PropertyValue $Task "planner_metadata"
  (
    [string](Get-PropertyValue $metadata "adapter") -eq "mg338-codex-artifact-persistence-recovery" -and
    [string](Get-PropertyValue $metadata "reason") -eq "mg338_one_live_codex_report_recovery_task" -and
    [string](Get-PropertyValue $metadata "source_run_id") -eq "mega-goal-338-codex-artifact-persistence-recovery" -and
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

function Test-InputFilesExist {
  foreach ($relative in @($InputManifest, $InputSummary, $InputMetrics)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { return $false }
  }
  $true
}

function Test-OldOutputResidue {
  $outputFull = Join-Path $RepoRoot $OutputDir
  if (-not (Test-Path -LiteralPath $outputFull -PathType Container)) { return $false }
  [bool](@(Get-ChildItem -LiteralPath $outputFull -Force -ErrorAction SilentlyContinue).Count -gt 0)
}

function New-CodexReportTaskPayload {
  [pscustomobject]@{
    task_id = $TargetTaskId
    project_id = $ProjectId
    title = "MG338 Codex artifact persistence recovery"
    body = "Generate one bounded Markdown report from MG336 manifest, summary, and metrics only. Do not run MATLAB, create PRs, inspect secrets, or include raw logs."
    prompt_summary = "MG338 deterministic Codex artifact persistence recovery. Safe summary/metrics input only; no raw prompt or logs persisted."
    risk = "medium"
    source = "manual"
    task_type = "codex-analysis-report"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @(
      "fixed Codex analysis report runner completed",
      "report.md exists under .agent/tmp/codex-analysis-report/live-codex-analysis-report-task-338-001/",
      "report path is not truncated",
      "server evidence lists only actual existing files",
      "fallback report is clearly marked if used",
      "raw_codex_log_included=false",
      "raw_prompt_included=false",
      "raw_stdout_included=false",
      "raw_stderr_included=false",
      "matlab_run_called=false",
      "token_printed=false"
    )
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = @{
      adapter = "mg338-codex-artifact-persistence-recovery"
      decision = "continue"
      reason = "mg338_one_live_codex_report_recovery_task"
      task_type = "codex-analysis-report"
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      evidence_schema = @($EvidenceSchemaId)
      input_files = @($InputManifest, $InputSummary, $InputMetrics)
      output_report = $OutputReport
      allowed_paths = @($AllowedPaths)
      blocked_paths = @($BlockedPaths)
      validation = @(
        "report.md exists",
        "report_size_bytes greater than zero",
        "validation_status=passed",
        "raw logs and raw prompt are not included",
        "token_printed=false"
      )
      expected_outputs = @($OutputReport)
      do_not_reuse_task_ids = @($DoNotReuseTaskId)
      stop_criteria_status = @("complete_exact_live_codex_artifact_recovery_then_stop")
      source_run_id = "mega-goal-338-codex-artifact-persistence-recovery"
      depends_on_task_id = "live-matlab-golden-task-336-001"
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
}

function Invoke-CreatePreview {
  $targetTaskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { $TargetTaskId } else { $TaskId }
  $project = Get-ProjectView
  $existing = Get-TaskViewById -RequestedTaskId $targetTaskId
  $oldTask = Get-TaskViewById -RequestedTaskId $DoNotReuseTaskId
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($targetTaskId -ne $TargetTaskId) { $blockers.Add("unexpected_live_codex_report_recovery_task_id") | Out-Null }
  if ($targetTaskId -eq $DoNotReuseTaskId) { $blockers.Add("old_task_reuse_refused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $blockers.Add("unexpected_template_id") | Out-Null }
  if (-not $project) { $blockers.Add("project_not_found") | Out-Null }
  if (-not (Test-InputFilesExist)) { $blockers.Add("mg336_input_files_missing") | Out-Null }
  if ($existing -and -not (Test-TaskHasCodexReportMetadata $existing)) { $blockers.Add("existing_task_not_mg338_codex_artifact_recovery") | Out-Null }
  if ($existing -and [string]$existing.status -notin @("queued")) { $blockers.Add("existing_task_not_safe_queued_state") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_create_preview.v1"
    ok = ($blockers.Count -eq 0)
    mode = "preview"
    project_id = $ProjectId
    task_id = $targetTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskId)
    old_task_seen = [bool]$oldTask
    old_task_requeued = $false
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    input_manifest_path = $InputManifest
    input_summary_path = $InputSummary
    input_metrics_path = $InputMetrics
    input_files_exist = Test-InputFilesExist
    output_report_path = $OutputReport
    task_exists = [bool]$existing
    would_create_task = -not [bool]$existing -and $blockers.Count -eq 0
    task_created = $false
    blockers = @($blockers)
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    required_capabilities = @($RequiredCapabilities)
    claim_created = $false
    execution_started = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  }
}

function Invoke-CreateApply {
  $preview = Invoke-CreatePreview
  if (-not $preview.ok) {
    return [pscustomobject]@{
      schema = "skybridge.live_codex_analysis_report_recovery_create_result.v1"
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
      matlab_run_called = $false
      worker_loop_started = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      pr_created = $false
      token_printed = $false
    }
  }
  if (-not $Confirm -or $ConfirmationText -ne $CreateConfirmationPhrase) {
    return [pscustomobject]@{
      schema = "skybridge.live_codex_analysis_report_recovery_create_result.v1"
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
      matlab_run_called = $false
      worker_loop_started = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      pr_created = $false
      token_printed = $false
    }
  }
  if ($preview.task_exists) {
    return [pscustomobject]@{
      schema = "skybridge.live_codex_analysis_report_recovery_create_result.v1"
      ok = $true
      mode = "apply"
      project_id = $ProjectId
      task_id = $preview.task_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      task_created = $false
      task_already_present = $true
      review_reason = "existing_mg338_codex_artifact_recovery_task_reused_without_requeue"
      blockers = @()
      claim_created = $false
      execution_started = $false
      matlab_run_called = $false
      worker_loop_started = $false
      arbitrary_shell_enabled = $false
      project_control_unpaused = $false
      pr_created = $false
      token_printed = $false
    }
  }
  $response = Invoke-CodexReportApi -Method POST -Path "/v1/tasks" -Body (New-CodexReportTaskPayload)
  $created = ($response.status_code -ge 200 -and $response.status_code -lt 300)
  [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_create_result.v1"
    ok = $created
    mode = "apply"
    project_id = $ProjectId
    task_id = $preview.task_id
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    task_created = $created
    task_status = if ($created) { [string]$response.body.task.status } else { "unknown" }
    review_reason = if ($created) { "exact_confirmation_received_created_one_live_codex_report_recovery_task" } else { "task_create_failed" }
    blockers = if ($created) { @() } else { @("task_create_failed") }
    claim_created = $false
    execution_started = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  }
}

function Test-RunEligibility {
  param($Task, $Worker, $RunnerPreview)
  $reasons = New-Object System.Collections.Generic.List[string]
  $template = if ($Task) { Get-TaskTemplateId $Task } else { "" }
  $runner = if ($Task) { Get-TaskRunnerId $Task } else { "" }
  $workerStatus = "unknown"
  if ([string]::IsNullOrWhiteSpace($WorkerId) -or $WorkerId -ne $WorkerIdTarget) { $reasons.Add("worker_id_must_be_jerry_win_local_01") | Out-Null }
  if ($TaskId -ne $TargetTaskId) { $reasons.Add("unexpected_live_codex_report_recovery_task_id") | Out-Null }
  if ($TaskId -eq $DoNotReuseTaskId) { $reasons.Add("old_task_reuse_refused") | Out-Null }
  if ($TemplateId -ne $TemplateIdTarget) { $reasons.Add("unexpected_template_id") | Out-Null }
  if (-not (Test-InputFilesExist)) { $reasons.Add("mg336_input_files_missing") | Out-Null }
  if (Test-OldOutputResidue) { $reasons.Add("old_output_residue_present") | Out-Null }
  if ($Worker) {
    $workerStatus = [string]$Worker.status
    if ([string]$Worker.worker_id -ne $WorkerIdTarget) { $reasons.Add("worker_id_mismatch") | Out-Null }
    if ([string]$Worker.status -ne "online") { $reasons.Add("worker_not_online") | Out-Null }
    $capabilities = @(ConvertTo-Array $Worker.capabilities | ForEach-Object { [string]$_ })
    if ($capabilities -notcontains "codex") { $reasons.Add("worker_missing_codex_capability") | Out-Null }
  } else {
    $reasons.Add("worker_not_registered_or_offline") | Out-Null
  }
  if ($Task) {
    if ([string]$Task.task_id -ne $TargetTaskId) { $reasons.Add("selected_task_id_mismatch") | Out-Null }
    if ([string]$Task.task_id -eq $DoNotReuseTaskId) { $reasons.Add("old_task_reuse_refused") | Out-Null }
    if ([string]$Task.project_id -ne $ProjectId) { $reasons.Add("project_id_mismatch") | Out-Null }
    if ([string]$Task.status -ne "queued") {
      if ([string]$Task.status -in @("completed", "cancelled", "blocked", "failed")) { $reasons.Add("target_task_terminal_or_blocked") | Out-Null }
      else { $reasons.Add("target_task_not_queued") | Out-Null }
    }
    if ([string]$Task.risk -notin @("low", "medium")) { $reasons.Add("risk_not_low_or_medium") | Out-Null }
    if ($template -ne $TemplateIdTarget) { $reasons.Add("template_not_supported_mg338_codex_report_recovery") | Out-Null }
    if ($runner -ne $RunnerIdTarget) { $reasons.Add("runner_not_supported_mg338_codex_report_recovery") | Out-Null }
    if ($Task.lease -and [string]$Task.lease.lease_status -eq "active") { $reasons.Add("active_lease_exists") | Out-Null }
    if ($Task.claim) { $reasons.Add("existing_claim_residue") | Out-Null }
    if (-not (Test-TaskHasCodexReportMetadata $Task)) { $reasons.Add("task_not_created_by_mg338_codex_artifact_recovery") | Out-Null }
    if (Test-UnsafeText ([string]$Task.body)) { $reasons.Add("unsafe_path_or_text_detected") | Out-Null }
    $required = @(ConvertTo-Array $Task.required_capabilities | ForEach-Object { [string]$_ })
    if (-not (Test-ContainsAll $required $RequiredCapabilities)) { $reasons.Add("task_missing_codex_report_capabilities") | Out-Null }
    $allowed = @(ConvertTo-Array $Task.allowed_paths | ForEach-Object { [string]$_ })
    if (-not (Test-Subset $allowed $AllowedPaths)) { $reasons.Add("allowed_paths_outside_codex_report_policy") | Out-Null }
  } else {
    $reasons.Add("target_task_not_found") | Out-Null
  }
  if ($RunnerPreview.ok -ne $true) {
    $reasons.Add("runner_preview_blocked") | Out-Null
    foreach ($blocker in @(ConvertTo-Array $RunnerPreview.blockers)) { $reasons.Add([string]$blocker) | Out-Null }
  }
  if ($RunnerPreview.codex_available -ne $true) { $reasons.Add("codex_not_found") | Out-Null }
  if ([string]$RunnerPreview.output_report_path -ne $OutputReport) { $reasons.Add("output_path_invalid") | Out-Null }
  [pscustomobject]@{
    task = $Task
    eligible = ($reasons.Count -eq 0)
    rejected_reason = (@($reasons.ToArray() | Select-Object -Unique) -join ";")
    selected_task_count = if ($reasons.Count -eq 0) { 1 } else { 0 }
    allowed_paths_checked = [bool]$Task
    blocked_paths_checked = [bool]$Task
    cloud_worker_status = $workerStatus
  }
}

function New-RunRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Eligibility,
    [bool]$ClaimCreated = $false,
    [bool]$ExecutionStarted = $false,
    [bool]$ExecutionCompleted = $false,
    [bool]$ExecutionFailed = $false,
    $Evidence = $null,
    $HeartbeatRefresh = $null,
    [string]$FinalTaskState = "not_run",
    [string]$ResultSummary = ""
  )
  [pscustomobject]@{
    schema = if ($Mode -eq "preview") { "skybridge.live_codex_analysis_report_recovery_run_preview.v1" } else { "skybridge.live_codex_analysis_report_recovery_run_result.v1" }
    ok = $Ok
    mode = $Mode
    worker_id = $WorkerId
    project_id = $ProjectId
    task_id = $TaskId
    expected_task_id = $TargetTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskId)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    evidence_schema = $EvidenceSchemaId
    input_manifest_path = $InputManifest
    input_summary_path = $InputSummary
    input_metrics_path = $InputMetrics
    output_report_path = $OutputReport
    selected = [bool]$Eligibility.eligible
    eligible = [bool]$Eligibility.eligible
    selected_task_count = [int]$Eligibility.selected_task_count
    rejected_reason = [string]$Eligibility.rejected_reason
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
    expected_outputs_missing = if ($Evidence) { @($Evidence.expected_outputs_missing) } else { @($OutputReport) }
    validation_status = if ($Evidence) { [string]$Evidence.validation_status } elseif ($Ok) { "preview_only" } else { "blocked" }
    fallback_report_used = if ($Evidence) { [bool]$Evidence.fallback_report_used } else { $false }
    report_exists = if ($Evidence) { [bool]$Evidence.report_exists } else { $false }
    report_size_bytes = if ($Evidence) { [int64]$Evidence.report_size_bytes } else { 0 }
    result_summary = if (-not [string]::IsNullOrWhiteSpace($ResultSummary)) { $ResultSummary } elseif ($Ok) { "MG338 exact Codex artifact recovery task is eligible for fixed-runner apply." } else { "MG338 Codex artifact recovery task is not eligible for live apply." }
    final_task_state = $FinalTaskState
    cloud_worker_status = [string]$Eligibility.cloud_worker_status
    heartbeat_refresh = $HeartbeatRefresh
    codex_invoked = if ($Evidence) { [bool]$Evidence.codex_invoked } else { $false }
    codex_exit_code = if ($Evidence) { $Evidence.codex_exit_code } else { $null }
    codex_failure_category = if ($Evidence) { [string]$Evidence.codex_failure_category } else { "" }
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    pr_created = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Invoke-RunPreview {
  if ($TaskId -ne $TargetTaskId) {
    $dummy = [pscustomobject]@{
      eligible = $false
      rejected_reason = if ($TaskId -eq $DoNotReuseTaskId) { "old_task_reuse_refused" } else { "unexpected_live_codex_report_recovery_task_id" }
      selected_task_count = 0
      allowed_paths_checked = $false
      blocked_paths_checked = $false
      cloud_worker_status = "unknown"
    }
    return New-RunRecord -Mode preview -Ok $false -Eligibility $dummy
  }
  $worker = Get-WorkerView
  $task = Get-TaskViewById -RequestedTaskId $TaskId
  $runnerPreview = Invoke-Runner -RunnerCommand "preview"
  $eligibility = Test-RunEligibility -Task $task -Worker $worker -RunnerPreview $runnerPreview
  New-RunRecord -Mode preview -Ok ([bool]$eligibility.eligible) -Eligibility $eligibility
}

function Get-PostHeartbeatEligibility {
  $worker = Get-WorkerView
  $task = Get-TaskViewById -RequestedTaskId $TaskId
  $runnerPreview = Invoke-Runner -RunnerCommand "preview"
  Test-RunEligibility -Task $task -Worker $worker -RunnerPreview $runnerPreview
}

function New-FailureEvidence {
  param([string]$Category, [string]$Summary)
  [pscustomobject]@{
    schema = $EvidenceSchemaId
    ok = $false
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    input_manifest_path = $InputManifest
    input_summary_path = $InputSummary
    input_metrics_path = $InputMetrics
    input_manifest_exists = Test-InputFilesExist
    input_summary_exists = Test-InputFilesExist
    input_metrics_exists = Test-InputFilesExist
    output_report_path = $OutputReport
    report_exists = $false
    report_size_bytes = 0
    fallback_report_used = $false
    validation_status = "failed"
    codex_invoked = $false
    codex_exit_code = $null
    codex_failure_category = $Category
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    changed_files = @()
    existing_outputs = @()
    expected_outputs_missing = @($OutputReport)
    report_validation_errors = @($Category)
    result_summary = $Summary
    project_control_unpaused = $false
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    pr_created = $false
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
      input_manifest_path = [string]$Evidence.input_manifest_path
      input_summary_path = [string]$Evidence.input_summary_path
      input_metrics_path = [string]$Evidence.input_metrics_path
      input_manifest_exists = [bool]$Evidence.input_manifest_exists
      input_summary_exists = [bool]$Evidence.input_summary_exists
      input_metrics_exists = [bool]$Evidence.input_metrics_exists
      output_report_path = [string]$Evidence.output_report_path
      report_exists = [bool]$Evidence.report_exists
      report_size_bytes = [int64]$Evidence.report_size_bytes
      fallback_report_used = [bool]$Evidence.fallback_report_used
      validation_status = [string]$Evidence.validation_status
      codex_invoked = [bool]$Evidence.codex_invoked
      codex_exit_code = $Evidence.codex_exit_code
      codex_failure_category = [string]$Evidence.codex_failure_category
      changed_files = @($Evidence.changed_files)
      existing_outputs = @($Evidence.existing_outputs)
      expected_outputs_missing = @($Evidence.expected_outputs_missing)
      report_validation_errors = @($Evidence.report_validation_errors)
      risk_status = "medium_fixed_codex_artifact_recovery"
      summary = [string]$Evidence.result_summary
      raw_codex_log_included = $false
      raw_prompt_included = $false
      raw_stdout_included = $false
      raw_stderr_included = $false
      matlab_run_called = $false
      arbitrary_shell_enabled = $false
      worker_loop_started = $false
      project_control_unpaused = $false
      pr_created = $false
      token_printed = $false
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
}

function Invoke-RunApply {
  $preview = Invoke-RunPreview
  if (-not $Confirm -or $ConfirmationText -ne $RunConfirmationPhrase) {
    $preview.rejected_reason = "missing_exact_confirmation"
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ResultSummary "Exact MG338 run confirmation is required before claim/start/Codex artifact recovery apply."
  }

  $heartbeat = $null
  if (-not $preview.ok -and [string]$preview.rejected_reason -match "worker_not_online|worker_not_registered_or_offline") {
    $heartbeat = Invoke-HeartbeatRefresh
    $postHeartbeat = Get-PostHeartbeatEligibility
    if (-not $postHeartbeat.eligible) {
      return New-RunRecord -Mode apply -Ok $false -Eligibility $postHeartbeat -HeartbeatRefresh $heartbeat -ResultSummary "Worker heartbeat refresh did not leave the exact MG338 task eligible; no claim was created."
    }
    $preview = New-RunRecord -Mode preview -Ok $true -Eligibility $postHeartbeat
  }
  if (-not $preview.ok) { return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -HeartbeatRefresh $heartbeat -ResultSummary $preview.result_summary }

  $claim = Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -Body @{ worker_id = $WorkerId }
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    $preview.rejected_reason = "claim_failed"
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -HeartbeatRefresh $heartbeat -ResultSummary "Task claim failed before Codex report runner invocation."
  }

  $start = Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -Body @{ worker_id = $WorkerId }
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    $evidence = New-FailureEvidence -Category "start_failed" -Summary "Task start failed after claim; Codex was not invoked."
    Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body (Get-FinishBody -Evidence $evidence) | Out-Null
    return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionFailed $true -Evidence $evidence -HeartbeatRefresh $heartbeat -FinalTaskState "failed" -ResultSummary "Task start failed after claim; fail was attempted."
  }

  $runner = Invoke-Runner -RunnerCommand "apply" -WithConfirm
  $evidence = $runner.evidence
  if (-not $evidence) {
    $evidence = New-FailureEvidence -Category "codex_runner_no_evidence" -Summary "Codex report runner returned no evidence."
  }
  $finishBody = Get-FinishBody -Evidence $evidence

  if ($runner.ok -eq $true -and [string]$evidence.validation_status -eq "passed" -and [bool]$evidence.report_exists) {
    $complete = Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -Body $finishBody
    if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
      Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
      return New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -HeartbeatRefresh $heartbeat -FinalTaskState "failed" -ResultSummary "Codex report evidence passed but task completion failed; fail was attempted."
    }
    $finalTask = Get-TaskViewById -RequestedTaskId $TaskId
    return New-RunRecord -Mode apply -Ok $true -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionCompleted $true -Evidence $evidence -HeartbeatRefresh $heartbeat -FinalTaskState ([string]$finalTask.status) -ResultSummary ([string]$evidence.result_summary)
  }

  Invoke-CodexReportApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -Body $finishBody | Out-Null
  $failedTask = Get-TaskViewById -RequestedTaskId $TaskId
  New-RunRecord -Mode apply -Ok $false -Eligibility $preview -ClaimCreated $true -ExecutionStarted $true -ExecutionFailed $true -Evidence $evidence -HeartbeatRefresh $heartbeat -FinalTaskState ([string]$failedTask.status) -ResultSummary ([string]$evidence.result_summary)
}

function Get-Status {
  $version = Invoke-CodexReportApi -Method GET -Path "/v1/version"
  $worker = Invoke-CodexReportApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-CodexReportApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $runnerStatus = Invoke-Runner -RunnerCommand "preview"
  [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_status.v1"
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
    expected_task_id = $TargetTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskId)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    input_manifest_path = $InputManifest
    input_summary_path = $InputSummary
    input_metrics_path = $InputMetrics
    input_files_exist = Test-InputFilesExist
    output_report_path = $OutputReport
    report_exists = Test-Path -LiteralPath (Join-Path $RepoRoot $OutputReport) -PathType Leaf
    report_size_bytes = if (Test-Path -LiteralPath (Join-Path $RepoRoot $OutputReport) -PathType Leaf) { [int64](Get-Item -LiteralPath (Join-Path $RepoRoot $OutputReport)).Length } else { 0 }
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    task_status = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { [string]$task.body.task.status } else { "missing" }
    codex_available = [bool]$runnerStatus.codex_available
    runner_preview_blockers = @($runnerStatus.blockers)
    version_seen = ($version.status_code -ge 200 -and $version.status_code -lt 300)
    version_commit_sha = if ($version.status_code -ge 200 -and $version.status_code -lt 300) { [string]$version.body.commit_sha } else { "" }
    confirmation_required_create = $true
    confirmation_text_create = $CreateConfirmationPhrase
    confirmation_required_run = $true
    confirmation_text_run = $RunConfirmationPhrase
    claim_created = $false
    execution_started = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  }
}

function Get-Report {
  $worker = Invoke-CodexReportApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-CodexReportApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $taskBody = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { $task.body.task } else { $null }
  $evidenceSummary = if ($taskBody -and $taskBody.result) { $taskBody.result.evidence_summary } else { $null }
  [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_report.v1"
    ok = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    worker_id = $WorkerId
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    task_id = $TaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskId)
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    final_task_state = if ($taskBody) { [string]$taskBody.status } else { "missing" }
    assigned_worker_id = if ($taskBody) { [string]$taskBody.assigned_worker_id } else { "" }
    evidence_summary_present = [bool]$evidenceSummary
    evidence_summary = $evidenceSummary
    task_claimed_count = if ($taskBody -and $taskBody.claim) { 1 } else { 0 }
    old_task_claimed = $false
    claim_created = if ($taskBody -and $taskBody.claim) { $true } else { $false }
    execution_started = if ($taskBody -and [string]$taskBody.status -in @("running", "completed", "failed")) { $true } else { $false }
    output_report_path = $OutputReport
    output_report_exists = Test-Path -LiteralPath (Join-Path $RepoRoot $OutputReport) -PathType Leaf
    report_size_bytes = if (Test-Path -LiteralPath (Join-Path $RepoRoot $OutputReport) -PathType Leaf) { [int64](Get-Item -LiteralPath (Join-Path $RepoRoot $OutputReport)).Length } else { 0 }
    fallback_report_used = if ($evidenceSummary) { [bool]$evidenceSummary.fallback_report_used } else { $false }
    validation_status = if ($evidenceSummary) { [string]$evidenceSummary.validation_status } else { "missing" }
    changed_files = if ($evidenceSummary) { @($evidenceSummary.changed_files) } else { @() }
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  }
}

if ($Command -eq "status") {
  $result = Get-Status
} elseif ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_safe_summary.v1"
    ok = $true
    worker_id = $WorkerId
    task_id = $TaskId
    expected_task_id = $TargetTaskId
    do_not_reuse_task_ids = @($DoNotReuseTaskId)
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    output_report_path = $OutputReport
    next_safe_action = "preview_create_then_exact_confirm_create_then_preview_run_then_exact_confirm_run_one_codex_report_recovery_task"
    claim_created = $false
    execution_started = $false
    matlab_run_called = $false
    worker_loop_started = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  }
} elseif ($Command -eq "preview-create") {
  $result = Invoke-CreatePreview
} elseif ($Command -eq "apply-create") {
  $result = Invoke-CreateApply
} elseif ($Command -eq "preview-run") {
  $result = Invoke-RunPreview
} elseif ($Command -eq "apply-run") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_codex_analysis_report_recovery_apply_run.v1"
    ok = $false
    runner_result = Invoke-RunApply
    report = $null
    task_id = $TaskId
    worker_id = $WorkerId
    token_printed = $false
  }
  $result.ok = [bool]$result.runner_result.ok
  $result.report = Get-Report
  $result | Add-Member -NotePropertyName task_claimed_count -NotePropertyValue ([int]$result.runner_result.task_claimed_count)
  $result | Add-Member -NotePropertyName old_task_claimed -NotePropertyValue $false
  $result | Add-Member -NotePropertyName claim_created -NotePropertyValue ([bool]$result.runner_result.claim_created)
  $result | Add-Member -NotePropertyName execution_started -NotePropertyValue ([bool]$result.runner_result.execution_started)
  $result | Add-Member -NotePropertyName execution_completed -NotePropertyValue ([bool]$result.runner_result.execution_completed)
  $result | Add-Member -NotePropertyName execution_failed -NotePropertyValue ([bool]$result.runner_result.execution_failed)
  $result | Add-Member -NotePropertyName codex_invoked -NotePropertyValue ([bool]$result.runner_result.codex_invoked)
  $result | Add-Member -NotePropertyName fallback_report_used -NotePropertyValue ([bool]$result.runner_result.fallback_report_used)
  $result | Add-Member -NotePropertyName report_exists -NotePropertyValue ([bool]$result.runner_result.report_exists)
  $result | Add-Member -NotePropertyName report_size_bytes -NotePropertyValue ([int64]$result.runner_result.report_size_bytes)
  $result | Add-Member -NotePropertyName matlab_run_called -NotePropertyValue $false
  $result | Add-Member -NotePropertyName arbitrary_shell_enabled -NotePropertyValue $false
  $result | Add-Member -NotePropertyName worker_loop_started -NotePropertyValue $false
  $result | Add-Member -NotePropertyName unbounded_run_enabled -NotePropertyValue $false
  $result | Add-Member -NotePropertyName project_control_unpaused -NotePropertyValue $false
  $result | Add-Member -NotePropertyName pr_created -NotePropertyValue $false
} else {
  $result = Get-Report
}

if ($Json) {
  $result | ConvertTo-Json -Depth 32
} else {
  $result | Format-List
}
