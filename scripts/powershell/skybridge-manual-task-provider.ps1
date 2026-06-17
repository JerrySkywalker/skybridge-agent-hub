[CmdletBinding()]
param(
  [ValidateSet("status", "provider-list", "provider-check", "run-next-mock", "run-next-hermes-preview", "run-next-hermes-live-optin", "run-next-skybridge-hermes", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$AllowLive,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ManualTaskDir = Join-Path $RepoRoot ".agent\tmp\manual-task"
$QueuePath = Join-Path $ManualTaskDir "manual-task-queue.json"
$ProviderReportJson = Join-Path $ManualTaskDir "manual-task-provider-report.json"
$ServerHermesProviderReportJson = Join-Path $ManualTaskDir "server-hermes-provider-report.json"
$ServerHermesProviderReportMarkdown = Join-Path $ManualTaskDir "server-hermes-provider-report.md"
$ServerHermesPreviewReportJson = Join-Path $ManualTaskDir "server-hermes-preview-report.json"
$ServerHermesLiveOptInReportJson = Join-Path $ManualTaskDir "server-hermes-live-optin-report.json"
$HermesPreviewReportJson = Join-Path $ManualTaskDir "manual-task-hermes-preview-report.json"
$HermesLiveReportJson = Join-Path $ManualTaskDir "manual-task-hermes-live-optin-report.json"

function Test-ProviderUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  $unsafePattern = "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|`"api[_-]?key`"\s*:\s*`"[^`"]+`"|`"token`"\s*:\s*`"[^`"]+`"|`"password`"\s*:\s*`"[^`"]+`"|`"secret`"\s*:\s*`"[^`"]+`"|cookie\s*[:=]|raw_prompt\s*[:=]|raw_request\s*[:=]|raw_response\s*[:=]|raw_stdout|raw_stderr|raw_worker_log|raw_ci_log|env_dump|environment dump|$tokenTrue"
  return $Text -match $unsafePattern
}

function ConvertTo-ProviderHash([string]$Text) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
}

function ConvertTo-ProviderSafePreview([string]$Text, [int]$MaxLength = 240) {
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

function Write-ProviderSafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 100
  if (Test-ProviderUnsafeText $text) {
    throw "Refusing unsafe manual task provider JSON."
  }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function New-ProviderRecord([string]$ProviderId, [string]$Status, [bool]$Configured, [bool]$LiveEnabled, [bool]$NetworkEnabled, [string]$Reason = "") {
  [pscustomobject]@{
    schema = "skybridge.manual_task_provider.v1"
    provider_id = $ProviderId
    status = $Status
    configured = $Configured
    deterministic = ($ProviderId -eq "mock")
    network_enabled = $NetworkEnabled
    hermes_live_call_enabled = $false
    server_mediated_llm_inference_enabled = ($ProviderId -eq "skybridge_server_hermes" -and $Configured)
    cloud_hermes_provider_enabled = ($ProviderId -eq "skybridge_server_hermes" -and $LiveEnabled)
    remote_llm_inference_enabled = $false
    disabled_by_default = ($ProviderId -ne "mock")
    deprecated = ($ProviderId -eq "hermes_deepseek")
    preview_only = ($ProviderId -eq "hermes_deepseek")
    ci_disabled = (Test-Ci)
    config_path = if ($ProviderId -eq "skybridge_server_hermes") { "server-side HERMES_API_BASE + HERMES_API_KEY or token file" } elseif ($ProviderId -eq "hermes_deepseek") { "deprecated local-direct preview only" } else { $null }
    config_values_redacted = $true
    raw_request_persisted = $false
    raw_response_persisted = $false
    reason = $Reason
    token_printed = $false
  }
}

function Test-Ci {
  ($env:CI -eq "true" -or $env:GITHUB_ACTIONS -eq "true" -or $env:SKYBRIDGE_CI -eq "true")
}

function Get-ServerHermesConfigSummary {
  [pscustomobject]@{
    schema = "skybridge.manual_task_provider_config.v1"
    provider_id = "skybridge_server_hermes"
    server_config_only = $true
    api_base_configured = -not [string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)
    api_key_present = (-not [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) -or (-not [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY_FILE))
    client_secret_required = $false
    timeout_seconds = 60
    max_response_chars = 2000
    credential_values_exposed = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
}

function Get-HermesConfigSummary {
  [pscustomobject]@{
    schema = "skybridge.manual_task_provider_config.v1"
    provider_id = "hermes_deepseek"
    deprecated = $true
    preview_only = $true
    config_path = "deprecated local-direct config ignored"
    config_present = $false
    endpoint_configured = $false
    model_configured = $false
    timeout_seconds = 60
    max_response_chars = 2000
    live_enabled = $false
    ci_disabled = Test-Ci
    credential_values_exposed = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
}

function New-EmptyQueue {
  [pscustomobject]@{
    schema = "skybridge.manual_task_queue.v1"
    queue_id = "local-manual-task-queue"
    provider = New-ProviderRecord "mock" "enabled" $true $false $false
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

function Read-ProviderQueue {
  if (-not (Test-Path -LiteralPath $QueuePath)) { return New-EmptyQueue }
  $text = Get-Content -Raw -LiteralPath $QueuePath
  if (Test-ProviderUnsafeText $text) { throw "Unsafe manual task queue state." }
  $queue = $text | ConvertFrom-Json
  if (-not $queue.PSObject.Properties["tasks"]) { $queue | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force }
  if (-not $queue.PSObject.Properties["provider_status"]) { $queue | Add-Member -NotePropertyName provider_status -NotePropertyValue "mock_default" -Force }
  if (-not $queue.PSObject.Properties["remote_llm_inference_enabled"]) { $queue | Add-Member -NotePropertyName remote_llm_inference_enabled -NotePropertyValue $false -Force }
  $queue
}

function Save-ProviderQueue($Queue) {
  $Queue.updated_at = (Get-Date).ToUniversalTime().ToString("o")
  Write-ProviderSafeJson $QueuePath $Queue
  $Queue
}

function Get-NextQueuedTask($Queue) {
  $queuedTasks = @($Queue.tasks | Where-Object { $_.status -eq "queued" })
  if ($queuedTasks.Count -eq 0) { return $null }
  $queuedTasks[0]
}

function New-PromptWrapper([object]$Task) {
  @(
    "You are answering a SkyBridge Manual Task Queue provider preview.",
    "Do not execute commands, suggest command execution as an action taken, or claim that a command ran.",
    "Do not fabricate realtime data. If the user asks for weather and no live weather tool is available, say realtime weather cannot be verified.",
    "Return a concise safe answer for the human operator.",
    "",
    "Sanitized manual task input preview:",
    ([string]$Task.input_preview)
  ) -join "`n"
}

function Set-TaskResult([object]$Task, [object]$Result) {
  $now = (Get-Date).ToUniversalTime().ToString("o")
  $Task.status = $Result.status
  $Task | Add-Member -NotePropertyName provider_id -NotePropertyValue $Result.provider_id -Force
  $Task | Add-Member -NotePropertyName provider_status -NotePropertyValue $Result.provider_status -Force
  $Task | Add-Member -NotePropertyName result_preview -NotePropertyValue $Result.result_preview -Force
  $Task | Add-Member -NotePropertyName result_hash -NotePropertyValue $Result.result_hash -Force
  $Task | Add-Member -NotePropertyName error_summary -NotePropertyValue $Result.error_summary -Force
  $Task | Add-Member -NotePropertyName duration_ms -NotePropertyValue $Result.duration_ms -Force
  $Task | Add-Member -NotePropertyName live_call_performed -NotePropertyValue $Result.live_call_performed -Force
  $Task | Add-Member -NotePropertyName server_mediated_llm_inference_enabled -NotePropertyValue $Result.server_mediated_llm_inference_enabled -Force
  $Task | Add-Member -NotePropertyName cloud_hermes_provider_enabled -NotePropertyValue $Result.cloud_hermes_provider_enabled -Force
  $Task | Add-Member -NotePropertyName remote_llm_inference_enabled -NotePropertyValue $Result.remote_llm_inference_enabled -Force
  $Task | Add-Member -NotePropertyName output_executed -NotePropertyValue $false -Force
  $Task | Add-Member -NotePropertyName command_executed -NotePropertyValue $false -Force
  $Task | Add-Member -NotePropertyName completed_at -NotePropertyValue $now -Force
  $Task.updated_at = $now
}

function Invoke-ProviderMock {
  $queue = Read-ProviderQueue
  $task = Get-NextQueuedTask $queue
  if ($null -eq $task) {
    return [pscustomobject]@{
      schema = "skybridge.manual_task_result.v1"
      status = "blocked"
      provider_id = "mock"
      provider_status = "mock_default"
      result_preview = "Mock provider blocked: no queued manual task."
      error_summary = "no_queued_task"
      duration_ms = 0
      live_call_performed = $false
      server_mediated_llm_inference_enabled = $false
      cloud_hermes_provider_enabled = $false
      remote_llm_inference_enabled = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      output_executed = $false
      token_printed = $false
    }
  }
  $started = Get-Date
  $task.status = "running"
  $task.updated_at = $started.ToUniversalTime().ToString("o")
  $prefix = ([string]$task.input_hash).Substring(0, 12)
  $classification = if ($task.command_text_detected -eq $true) { "command_text_detected_no_execution" } else { "safe_question" }
  $preview = "Mock reply ${prefix}: recorded sanitized local question; classification=$classification."
  $result = [pscustomobject]@{
    schema = "skybridge.manual_task_result.v1"
    task_id = $task.task_id
    provider = New-ProviderRecord "mock" "enabled" $true $false $false
    provider_id = "mock"
    provider_status = "mock_default"
    status = "succeeded"
    result_preview = $preview
    result_hash = ConvertTo-ProviderHash $preview
    error_summary = ""
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    live_call_performed = $false
    server_mediated_llm_inference_enabled = $false
    cloud_hermes_provider_enabled = $false
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
  Set-TaskResult $task $result
  $queue.provider = New-ProviderRecord "mock" "enabled" $true $false $false
  $queue.provider_status = "mock_default"
  $queue.remote_llm_inference_enabled = $false
  Save-ProviderQueue $queue | Out-Null
  $result
}

function Invoke-HermesPreview {
  $queue = Read-ProviderQueue
  $task = Get-NextQueuedTask $queue
  if ($null -eq $task) {
    return [pscustomobject]@{
      schema = "skybridge.manual_task_result.v1"
      status = "blocked"
      provider_id = "hermes_deepseek"
      provider_status = "preview_no_queued_task"
      result_preview = "Hermes DeepSeek preview blocked: no queued manual task."
      error_summary = "no_queued_task"
      duration_ms = 0
      live_call_performed = $false
      server_mediated_llm_inference_enabled = $false
      cloud_hermes_provider_enabled = $false
      remote_llm_inference_enabled = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      output_executed = $false
      token_printed = $false
    }
  }
  $started = Get-Date
  $task.status = "running"
  $task.updated_at = $started.ToUniversalTime().ToString("o")
  $promptHash = ConvertTo-ProviderHash (New-PromptWrapper $task)
  $preview = "Hermes DeepSeek preview $($promptHash.Substring(0, 12)): deprecated local-direct provider; preview_no_network; use skybridge_server_hermes for server-mediated Hermes."
  $result = [pscustomobject]@{
    schema = "skybridge.manual_task_result.v1"
    task_id = $task.task_id
    provider_id = "hermes_deepseek"
    provider_status = "preview_no_network"
    status = "succeeded"
    result_preview = $preview
    result_hash = ConvertTo-ProviderHash $preview
    error_summary = ""
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    live_call_performed = $false
    server_mediated_llm_inference_enabled = $false
    cloud_hermes_provider_enabled = $false
    remote_llm_inference_enabled = $false
    output_executed = $false
    command_executed = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    queue_apply_enabled = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
  Set-TaskResult $task $result
  $queue.provider = New-ProviderRecord "hermes_deepseek" "preview_no_network" $false $false $false
  $queue.provider_status = "hermes_preview_no_network"
  $queue.remote_llm_inference_enabled = $false
  Save-ProviderQueue $queue | Out-Null
  Write-ProviderSafeJson $HermesPreviewReportJson $result
  $result
}

function Invoke-HermesLiveOptIn {
  $configSummary = Get-HermesConfigSummary
  $result = [pscustomobject]@{
    schema = "skybridge.manual_task_result.v1"
    provider_id = "hermes_deepseek"
    provider_status = "deprecated_local_direct_live_blocked"
    status = "blocked"
    result_preview = "Hermes local-direct live opt-in is deprecated and blocked; use provider_id=skybridge_server_hermes through the SkyBridge server."
    result_hash = ConvertTo-ProviderHash "deprecated_local_direct_live_blocked"
    error_summary = "deprecated_local_direct_live_blocked"
    config = $configSummary
    duration_ms = 0
    live_call_performed = $false
    server_mediated_llm_inference_enabled = $false
    cloud_hermes_provider_enabled = $false
    remote_llm_inference_enabled = $false
    output_executed = $false
    command_executed = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    queue_apply_enabled = $false
    raw_request_persisted = $false
    raw_response_persisted = $false
    token_printed = $false
  }
  Write-ProviderSafeJson $HermesLiveReportJson $result
  $result
}

function Invoke-SkyBridgeHermes {
  $queue = Read-ProviderQueue
  $task = Get-NextQueuedTask $queue
  if ($null -eq $task) {
    $result = [pscustomobject]@{
      schema = "skybridge.manual_task_result.v1"
      status = "blocked"
      provider_id = "skybridge_server_hermes"
      provider_status = "server_no_queued_task"
      result_preview = "SkyBridge server Hermes blocked: no queued manual task."
      error_summary = "no_queued_task"
      duration_ms = 0
      live_call_performed = $false
      server_mediated_llm_inference_enabled = $false
      cloud_hermes_provider_enabled = $false
      remote_llm_inference_enabled = $false
      output_executed = $false
      command_executed = $false
      workunit_created = $false
      task_created = $false
      task_claim_created = $false
      task_pr_created = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      queue_apply_enabled = $false
      raw_request_persisted = $false
      raw_response_persisted = $false
      token_printed = $false
    }
    Write-ProviderSafeJson $ServerHermesPreviewReportJson $result
    return $result
  }
  $apiBase = ($env:SKYBRIDGE_API_BASE ?? "http://127.0.0.1:8787").TrimEnd("/")
  $body = @{
    task_id = $task.task_id
    input_preview = $task.input_preview
  } | ConvertTo-Json -Depth 10
  try {
    $result = Invoke-RestMethod -Method Post -Uri "$apiBase/v1/manual-tasks/run-next/skybridge-hermes" -ContentType "application/json" -Body $body -TimeoutSec 70
  } catch {
    $summary = ConvertTo-ProviderSafePreview $_.Exception.GetType().Name 120
    $result = [pscustomobject]@{
      schema = "skybridge.manual_task_result.v1"
      task_id = $task.task_id
      status = "blocked"
      provider_id = "skybridge_server_hermes"
      provider_status = "server_unavailable_or_disabled"
      result_preview = "SkyBridge server Hermes blocked safely: $summary."
      result_hash = ConvertTo-ProviderHash "server_unavailable_or_disabled"
      error_summary = $summary
      duration_ms = 0
      live_call_performed = $false
      server_mediated_llm_inference_enabled = $false
      cloud_hermes_provider_enabled = $false
      remote_llm_inference_enabled = $false
      output_executed = $false
      command_executed = $false
      workunit_created = $false
      task_created = $false
      task_claim_created = $false
      task_pr_created = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      queue_apply_enabled = $false
      raw_request_persisted = $false
      raw_response_persisted = $false
      token_printed = $false
    }
  }
  Set-TaskResult $task $result
  $queue.provider = New-ProviderRecord "skybridge_server_hermes" $result.provider_status $true $result.cloud_hermes_provider_enabled $result.live_call_performed
  $queue.provider_status = $result.provider_status
  $queue.remote_llm_inference_enabled = $false
  Save-ProviderQueue $queue | Out-Null
  if ($result.live_call_performed -eq $true) { Write-ProviderSafeJson $ServerHermesLiveOptInReportJson $result } else { Write-ProviderSafeJson $ServerHermesPreviewReportJson $result }
  $result
}

function Get-ProviderList {
  $configSummary = Get-HermesConfigSummary
  $serverConfig = Get-ServerHermesConfigSummary
  [pscustomobject]@{
    schema = "skybridge.manual_task_provider_list.v1"
    default_provider_id = "mock"
    providers = @(
      (New-ProviderRecord "mock" "enabled" $true $false $false),
      (New-ProviderRecord "skybridge_server_hermes" $(if ($serverConfig.api_base_configured -and $serverConfig.api_key_present) { "configured_disabled_until_requested" } else { "disabled_missing_server_config" }) ($serverConfig.api_base_configured -and $serverConfig.api_key_present) ($serverConfig.api_base_configured -and $serverConfig.api_key_present) ($serverConfig.api_base_configured -and $serverConfig.api_key_present)),
      (New-ProviderRecord "hermes_deepseek" "deprecated_preview_no_network" $false $false $false)
    )
    hermes_config = $configSummary
    server_hermes_config = $serverConfig
    server_mediated_provider_id = "skybridge_server_hermes"
    local_direct_deprecated = $true
    client_secret_required = $false
    live_call_disabled_by_default = $true
    token_printed = $false
  }
}

function New-ProviderReport {
  $queue = Read-ProviderQueue
  $list = Get-ProviderList
  $report = [pscustomobject]@{
    schema = "skybridge.manual_task_provider_report.v1"
    status = "ready"
    queue_id = $queue.queue_id
    default_provider_id = "mock"
    provider_list = $list
    queue_provider_status = $queue.provider_status
    hermes_disabled_by_default = $true
    server_mediated_llm_inference_enabled = $false
    cloud_hermes_provider_enabled = $false
    local_direct_deprecated = $true
    no_hermes_live_call_in_ci = $true
    raw_request_persisted = $false
    raw_response_persisted = $false
    worker_execution_started = $false
    workunit_created = $false
    task_created = $false
    task_claim_created = $false
    task_pr_created = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    output_executed = $false
    report_artifacts_written = $true
    token_printed = $false
  }
  Write-ProviderSafeJson $ProviderReportJson $report
  Write-ProviderSafeJson $ServerHermesProviderReportJson $report
  Write-SafeProviderMarkdown $ServerHermesProviderReportMarkdown @(
    "# Server-mediated Hermes Manual Task Provider",
    "",
    "- provider_id: skybridge_server_hermes",
    "- default_provider_id: mock",
    "- local_direct_hermes_deepseek: deprecated preview-only",
    "- client_secret_required: false",
    "- raw_request_persisted: false",
    "- raw_response_persisted: false",
    "- output_executed: false",
    "- remote_execution_enabled: false",
    "- arbitrary_command_enabled: false",
    "- queue_apply_enabled: false",
    "- token_printed=false"
  )
  $report
}

function Write-SafeProviderMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-ProviderUnsafeText $text) { throw "Refusing unsafe manual task provider markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-ProviderCommand {
  switch ($Command) {
    "status" { New-ProviderReport }
    "provider-list" { Get-ProviderList }
    "provider-check" { Get-HermesConfigSummary }
    "run-next-mock" { Invoke-ProviderMock }
    "run-next-hermes-preview" { Invoke-HermesPreview }
    "run-next-hermes-live-optin" { Invoke-HermesLiveOptIn }
    "run-next-skybridge-hermes" { Invoke-SkyBridgeHermes }
    "safe-summary" { [pscustomobject]@{ ok = $true; default_provider_id = "mock"; server_mediated_provider_id = "skybridge_server_hermes"; local_direct_deprecated = $true; client_secret_required = $false; hermes_disabled_by_default = $true; hermes_live_call_enabled = $false; server_mediated_llm_inference_enabled = $false; cloud_hermes_provider_enabled = $false; ci_disables_live_call = $true; raw_request_persisted = $false; raw_response_persisted = $false; output_executed = $false; worker_execution_started = $false; workunit_created = $false; task_created = $false; task_pr_created = $false; queue_apply_enabled = $false; token_printed = $false } }
    "report" { New-ProviderReport }
  }
}

$mutex = [System.Threading.Mutex]::new($false, "Global\SkyBridgeManualTaskQueue")
$lockTaken = $false
try {
  $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
  if (-not $lockTaken) { throw "Timed out waiting for manual task queue lock." }
  $Result = Invoke-ProviderCommand
} finally {
  if ($lockTaken) { $mutex.ReleaseMutex() | Out-Null }
  $mutex.Dispose()
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
