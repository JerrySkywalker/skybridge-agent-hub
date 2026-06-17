[CmdletBinding()]
param(
  [ValidateSet("status", "add-question", "list", "run-next-mock", "clear-completed", "safe-summary", "report")]
  [string]$Command = "status",
  [ValidateSet("mock", "hermes_deepseek")]
  [string]$ProviderId = "mock",
  [string]$Question = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\manual-task"
$QueuePath = Join-Path $ReportDir "manual-task-queue.json"
$ReportJson = Join-Path $ReportDir "manual-task-report.json"
$ReportMarkdown = Join-Path $ReportDir "manual-task-report.md"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|raw_prompt\s*[:=]|raw_transcript\s*[:=]|raw_request\s*[:=]|raw_response\s*[:=]|raw_stdout|raw_stderr|raw_worker_log|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function ConvertTo-Hash([string]$Text) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
}

function ConvertTo-SafePreview([string]$Text, [int]$MaxLength = 160) {
  $safe = [string]$Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[REDACTED]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9_.-]{12,}", "bearer [REDACTED]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "[REDACTED]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "[REDACTED]"
  $safe = $safe -replace "(?i)(token|password|secret|cookie|api[_-]?key)\s*[:=]\s*\S+", '$1=[REDACTED]'
  $safe = $safe -replace "\s+", " "
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return "$($safe.Substring(0, $MaxLength - 3))..." }
  $safe
}

function Test-CommandText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $Text -match "(?i)(cmd|command|shell|powershell|pwsh|bash|curl|wget)\s*[:=]|[;&|`$<>]"
}

function New-EmptyQueue {
  [pscustomobject]@{
    schema = "skybridge.manual_task_queue.v1"
    queue_id = "local-manual-task-queue"
    provider = [pscustomobject]@{
      schema = "skybridge.manual_task_provider.v1"
      provider_id = "mock"
      status = "enabled"
      deterministic = $true
      network_enabled = $false
      hermes_live_call_enabled = $false
      remote_llm_inference_enabled = $false
      disabled_by_default = $false
      raw_request_persisted = $false
      raw_response_persisted = $false
      token_printed = $false
    }
    provider_status = "mock_default"
    tasks = @()
    state_machine = @("queued", "running", "succeeded", "failed", "blocked", "cancelled")
    execution_enabled = $false
    worker_execution_started = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    queue_apply_enabled = $false
    start_all_enabled = $false
    start_queue_enabled = $false
    resume_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    host_mutation_performed = $false
    prompt_body_persisted = $false
    transcript_body_persisted = $false
    raw_logs_persisted = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    remote_llm_inference_enabled = $false
    token_printed = $false
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
  }
}

function Read-Queue {
  if (-not (Test-Path -LiteralPath $QueuePath)) { return New-EmptyQueue }
  $text = Get-Content -Raw -LiteralPath $QueuePath
  if (Test-UnsafeText $text) { throw "Unsafe manual task queue state." }
  $queue = $text | ConvertFrom-Json
  if (-not $queue.PSObject.Properties["tasks"]) { $queue | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force }
  if (-not $queue.PSObject.Properties["provider_status"]) { $queue | Add-Member -NotePropertyName provider_status -NotePropertyValue "mock_default" -Force }
  if (-not $queue.PSObject.Properties["remote_llm_inference_enabled"]) { $queue | Add-Member -NotePropertyName remote_llm_inference_enabled -NotePropertyValue $false -Force }
  $queue
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 100
  if (Test-UnsafeText $text) { throw "Refusing unsafe manual task JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe manual task markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Save-Queue($Queue) {
  $Queue.updated_at = (Get-Date).ToUniversalTime().ToString("o")
  Write-SafeJson $QueuePath $Queue
  $Queue
}

function Get-QueueSummary($Queue) {
  $tasks = @($Queue.tasks)
  [pscustomobject]@{
    schema = "skybridge.manual_task_queue.v1"
    queue_id = $Queue.queue_id
    provider_id = $Queue.provider.provider_id
    provider_status = $Queue.provider_status
    total = $tasks.Count
    queued = @($tasks | Where-Object { $_.status -eq "queued" }).Count
    running = @($tasks | Where-Object { $_.status -eq "running" }).Count
    succeeded = @($tasks | Where-Object { $_.status -eq "succeeded" }).Count
    failed = @($tasks | Where-Object { $_.status -eq "failed" }).Count
    blocked = @($tasks | Where-Object { $_.status -eq "blocked" }).Count
    cancelled = @($tasks | Where-Object { $_.status -eq "cancelled" }).Count
    hermes_live_call_enabled = $false
    mock_provider_enabled = $true
    hermes_deepseek_provider_available = $true
    default_provider_id = "mock"
    network_enabled = $false
    prompt_body_persisted = $false
    transcript_body_persisted = $false
    worker_execution_started = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    remote_llm_inference_enabled = [bool]$Queue.remote_llm_inference_enabled
    arbitrary_command_enabled = $false
    host_mutation_performed = $false
    token_printed = $false
  }
}

function Add-Question {
  if ([string]::IsNullOrWhiteSpace($Question)) { throw "add-question requires -Question." }
  $queue = Read-Queue
  $now = (Get-Date).ToUniversalTime().ToString("o")
  $hash = ConvertTo-Hash $Question
  $task = [pscustomobject]@{
    schema = "skybridge.manual_task.v1"
    task_id = "manual_$($hash.Substring(0, 12))"
    status = "queued"
    input_preview = ConvertTo-SafePreview $Question
    input_hash = $hash
    provider_id = $ProviderId
    provider_status = if ($ProviderId -eq "mock") { "mock_default" } else { "hermes_deepseek_disabled_by_default" }
    command_text_detected = Test-CommandText $Question
    prompt_body_persisted = $false
    created_at = $now
    updated_at = $now
    token_printed = $false
  }
  $queue.tasks = @($queue.tasks | Where-Object { $_.task_id -ne $task.task_id }) + @($task)
  Save-Queue $queue | Out-Null
  [pscustomobject]@{
    schema = "skybridge.manual_task_audit.v1"
    action = "add-question"
    accepted = $true
    task = $task
    prompt_body_persisted = $false
    token_printed = $false
  }
}

function Invoke-MockProvider([object]$Task) {
  $prefix = ([string]$Task.input_hash).Substring(0, 12)
  $classification = if ($Task.command_text_detected -eq $true) { "command_text_detected_no_execution" } else { "safe_question" }
  $preview = "Mock reply ${prefix}: recorded sanitized local question; classification=$classification."
  [pscustomobject]@{
    schema = "skybridge.manual_task_result.v1"
    task_id = $Task.task_id
    provider = [pscustomobject]@{
      schema = "skybridge.manual_task_provider.v1"
      provider_id = "mock"
      deterministic = $true
      network_enabled = $false
      hermes_live_call_enabled = $false
      raw_request_persisted = $false
      raw_response_persisted = $false
      token_printed = $false
    }
    status = "succeeded"
    provider_id = "mock"
    provider_status = "mock_default"
    result_preview = $preview
    result_hash = ConvertTo-Hash $preview
    duration_ms = 0
    error_summary = ""
    live_call_performed = $false
    remote_llm_inference_enabled = $false
    output_executed = $false
    command_executed = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    queue_apply_enabled = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
}

function Run-NextMock {
  $queue = Read-Queue
  $queuedTasks = @($queue.tasks | Where-Object { $_.status -eq "queued" })
  if ($queuedTasks.Count -eq 0) {
    return [pscustomobject]@{
      schema = "skybridge.manual_task_result.v1"
      status = "blocked"
      reason = "no_queued_task"
      provider_id = "mock"
      output_executed = $false
      token_printed = $false
    }
  }
  $task = $queuedTasks[0]
  $now = (Get-Date).ToUniversalTime().ToString("o")
  $task.status = "running"
  $task.updated_at = $now
  $started = Get-Date
  $result = Invoke-MockProvider $task
  $result.duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
  $task.status = "succeeded"
  $task | Add-Member -NotePropertyName result_preview -NotePropertyValue $result.result_preview -Force
  $task | Add-Member -NotePropertyName result_hash -NotePropertyValue $result.result_hash -Force
  $task | Add-Member -NotePropertyName provider_id -NotePropertyValue "mock" -Force
  $task | Add-Member -NotePropertyName provider_status -NotePropertyValue "mock_default" -Force
  $task | Add-Member -NotePropertyName duration_ms -NotePropertyValue $result.duration_ms -Force
  $task | Add-Member -NotePropertyName error_summary -NotePropertyValue "" -Force
  $task | Add-Member -NotePropertyName live_call_performed -NotePropertyValue $false -Force
  $task | Add-Member -NotePropertyName remote_llm_inference_enabled -NotePropertyValue $false -Force
  $task | Add-Member -NotePropertyName completed_at -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force
  $task.updated_at = $task.completed_at
  $task | Add-Member -NotePropertyName output_executed -NotePropertyValue $false -Force
  $task | Add-Member -NotePropertyName command_executed -NotePropertyValue $false -Force
  $queue.provider_status = "mock_default"
  $queue.remote_llm_inference_enabled = $false
  Save-Queue $queue | Out-Null
  $result
}

function Clear-Completed {
  $queue = Read-Queue
  $before = @($queue.tasks).Count
  $queue.tasks = @($queue.tasks | Where-Object { $_.status -notin @("succeeded", "failed", "cancelled") })
  Save-Queue $queue | Out-Null
  [pscustomobject]@{
    schema = "skybridge.manual_task_audit.v1"
    action = "clear-completed"
    cleared = ($before - @($queue.tasks).Count)
    remaining = @($queue.tasks).Count
    token_printed = $false
  }
}

function New-Report {
  $queue = Read-Queue
  $summary = Get-QueueSummary $queue
  $report = [pscustomobject]@{
    schema = "skybridge.manual_task_queue.v1"
    status = "ready"
    queue = $queue
    summary = $summary
    web_desktop_panel_status = "manual_controls_local_only"
    report_paths = @(
      ".agent/tmp/manual-task/manual-task-queue.json",
      ".agent/tmp/manual-task/manual-task-report.json",
      ".agent/tmp/manual-task/manual-task-report.md"
    )
    token_printed = $false
  }
  Write-SafeJson $ReportJson $report
  Write-SafeMarkdown $ReportMarkdown @(
    "# Manual Task Chat / Mock Queue MVP",
    "",
    "- schema: skybridge.manual_task_queue.v1",
    "- status: ready",
    "- provider_id: mock",
    "- hermes_live_call_enabled: false",
    "- network_enabled: false",
    "- worker_execution_started: false",
    "- workunit_created: false",
    "- task_created: false",
    "- task_claim_created: false",
    "- task_pr_created: false",
    "- queue_apply_enabled: false",
    "- prompt_body_persisted: false",
    "- transcript_body_persisted: false",
    "- token_printed=false"
  )
  $report
}

function Invoke-CommandBody {
  switch ($Command) {
    "status" { Get-QueueSummary (Read-Queue) }
    "add-question" { Add-Question }
    "list" { Read-Queue }
    "run-next-mock" { Run-NextMock }
    "clear-completed" { Clear-Completed }
    "safe-summary" { [pscustomobject]@{ ok = $true; provider_id = "mock"; default_provider_id = "mock"; hermes_deepseek_available = $true; hermes_live_call_enabled = $false; remote_llm_inference_enabled = $false; worker_execution_started = $false; workunit_created = $false; task_created = $false; task_pr_created = $false; queue_apply_enabled = $false; token_printed = $false } }
    "report" { New-Report }
  }
}

$mutex = [System.Threading.Mutex]::new($false, "Global\SkyBridgeManualTaskQueue")
$lockTaken = $false
try {
  $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
  if (-not $lockTaken) { throw "Timed out waiting for manual task queue lock." }
  $Result = Invoke-CommandBody
} finally {
  if ($lockTaken) { $mutex.ReleaseMutex() | Out-Null }
  $mutex.Dispose()
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
