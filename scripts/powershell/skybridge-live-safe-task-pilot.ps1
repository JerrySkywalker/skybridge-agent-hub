param(
  [ValidateSet("status", "preview-create", "apply-create", "preview-run", "apply-run", "report", "safe-summary")]
  [string]$Command = "status",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TaskId = "live-safe-template-task-332-001",
  [string]$TemplateId = "safe-local-smoke.v1",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$PilotTaskId = "live-safe-template-task-332-001"
$WorkerIdTarget = "jerry-win-local-01"
$TemplateIdTarget = "safe-local-smoke.v1"
$RunnerIdTarget = "safe-local-smoke-runner.v1"
$CreateConfirmationPhrase = "I_UNDERSTAND_CREATE_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"
$RunConfirmationPhrase = "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY"

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 24
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

function Invoke-PilotApi {
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
  [pscustomobject]@{
    status_code = [int]$response.StatusCode
    body = $body
  }
}

function Invoke-RunnerCommand {
  param(
    [string]$RunnerCommand,
    [switch]$WithConfirm
  )
  $runnerPath = Join-Path $PSScriptRoot "skybridge-worker-template-runner.ps1"
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $runnerPath,
    "-Command",
    $RunnerCommand,
    "-ApiBase",
    $ApiBase,
    "-WorkerId",
    $WorkerId,
    "-ProjectId",
    $ProjectId,
    "-TaskId",
    $TaskId,
    "-TemplateId",
    $TemplateId,
    "-MaxTasks",
    "1",
    "-Json"
  )
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
  if ($WithConfirm) {
    $args += "-Confirm"
    $args += @("-ConfirmationText", $ConfirmationText)
  }
  $raw = & pwsh @args
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-PilotStatus {
  $version = Invoke-PilotApi -Method GET -Path "/v1/version"
  $worker = Invoke-PilotApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-PilotApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_status.v1"
    ok = -not [string]::IsNullOrWhiteSpace($ApiBase)
    api_base_configured = -not [string]::IsNullOrWhiteSpace($ApiBase)
    api_base_host = if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { ([uri]$ApiBase).Host } else { "" }
    token_file_present = (-not [string]::IsNullOrWhiteSpace($TokenFile) -and (Test-Path -LiteralPath $TokenFile -PathType Leaf))
    token_value_printed = $false
    worker_id = $WorkerId
    expected_worker_id = $WorkerIdTarget
    worker_configured = -not [string]::IsNullOrWhiteSpace($WorkerId)
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    project_id = $ProjectId
    task_id = $TaskId
    template_id = $TemplateId
    runner_id = $RunnerIdTarget
    task_seen = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    task_status = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { [string]$task.body.task.status } else { "missing" }
    version_seen = ($version.status_code -ge 200 -and $version.status_code -lt 300)
    version_commit_sha = if ($version.status_code -ge 200 -and $version.status_code -lt 300) { [string]$version.body.commit_sha } else { "" }
    confirmation_required_create = $true
    confirmation_text_create = $CreateConfirmationPhrase
    confirmation_required_run = $true
    confirmation_text_run = $RunConfirmationPhrase
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

function Get-PilotReport {
  $worker = Invoke-PilotApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))"
  $task = Invoke-PilotApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
  $taskBody = if ($task.status_code -ge 200 -and $task.status_code -lt 300) { $task.body.task } else { $null }
  $evidenceSummary = if ($taskBody -and $taskBody.result) { $taskBody.result.evidence_summary } else { $null }
  [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_report.v1"
    ok = ($task.status_code -ge 200 -and $task.status_code -lt 300)
    worker_id = $WorkerId
    cloud_worker_seen = ($worker.status_code -ge 200 -and $worker.status_code -lt 300)
    cloud_worker_status = if ($worker.status_code -ge 200 -and $worker.status_code -lt 300) { [string]$worker.body.worker.status } else { "unknown" }
    task_id = $TaskId
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
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

if ($Command -eq "status") {
  $result = Get-PilotStatus
} elseif ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_safe_summary.v1"
    ok = $true
    worker_id = $WorkerId
    task_id = $TaskId
    template_id = $TemplateId
    runner_id = $RunnerIdTarget
    next_safe_action = "preview_create_then_exact_confirm_create_then_preview_run_then_exact_confirm_run"
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
} elseif ($Command -eq "preview-create") {
  $result = Invoke-RunnerCommand -RunnerCommand "create-live-safe-task-preview"
} elseif ($Command -eq "apply-create") {
  $result = Invoke-RunnerCommand -RunnerCommand "create-live-safe-task-apply" -WithConfirm
} elseif ($Command -eq "preview-run") {
  $result = Invoke-RunnerCommand -RunnerCommand "preview-live-one"
} elseif ($Command -eq "apply-run") {
  $runnerResult = Invoke-RunnerCommand -RunnerCommand "apply-live-one" -WithConfirm
  $result = [pscustomobject]@{
    schema = "skybridge.live_safe_task_pilot_apply_run.v1"
    ok = [bool]$runnerResult.ok
    runner_result = $runnerResult
    report = Get-PilotReport
    task_id = $TaskId
    worker_id = $WorkerId
    task_claimed_count = if ($runnerResult.task_claimed_count -ne $null) { [int]$runnerResult.task_claimed_count } else { 0 }
    old_task_claimed = $false
    claim_created = [bool]$runnerResult.claim_created
    execution_started = [bool]$runnerResult.execution_started
    execution_completed = [bool]$runnerResult.execution_completed
    execution_failed = [bool]$runnerResult.execution_failed
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
} else {
  $result = Get-PilotReport
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  $result | Format-List
}
