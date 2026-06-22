$ErrorActionPreference = "Stop"

function ConvertTo-SkyBridgeJson {
  param([Parameter(ValueFromPipeline = $true)]$InputObject)
  process {
    $InputObject | ConvertTo-Json -Depth 20
  }
}

function Read-SkyBridgeWorkerConfig {
  param([Parameter(Mandatory = $true)][string]$ConfigFile)

  $resolved = Resolve-Path -LiteralPath $ConfigFile -ErrorAction Stop
  $config = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($config.worker_id)) { throw "Worker config missing worker_id." }
  if ([string]::IsNullOrWhiteSpace($config.project_id)) { throw "Worker config missing project_id." }
  if ([string]::IsNullOrWhiteSpace($config.repo_path)) { throw "Worker config missing repo_path." }
  if ([string]::IsNullOrWhiteSpace($config.api_base)) { throw "Worker config missing api_base." }
  if ([string]::IsNullOrWhiteSpace($config.codex_sandbox)) { $config | Add-Member -NotePropertyName codex_sandbox -NotePropertyValue "workspace-write" -Force }
  if (-not $config.poll_interval_seconds) { $config | Add-Member -NotePropertyName poll_interval_seconds -NotePropertyValue 30 -Force }
  if (-not $config.max_task_runtime_minutes) { $config | Add-Member -NotePropertyName max_task_runtime_minutes -NotePropertyValue 30 -Force }
  if ($null -eq $config.codex_transport_max_retries) { $config | Add-Member -NotePropertyName codex_transport_max_retries -NotePropertyValue 1 -Force }
  if ($null -eq $config.auto_merge_enabled) { $config | Add-Member -NotePropertyName auto_merge_enabled -NotePropertyValue $false -Force }
  if ($null -eq $config.notification_enabled) { $config | Add-Member -NotePropertyName notification_enabled -NotePropertyValue $false -Force }
  if ([string]$config.auth_mode -eq "worker-token") { $config.auth_mode = "bearer_token" }
  return $config
}

function Get-SkyBridgeWorkerToken {
  param($Config)
  $envVar = if ($Config.token_env_var) { [string]$Config.token_env_var } else { "SKYBRIDGE_WORKER_TOKEN" }
  $token = [Environment]::GetEnvironmentVariable($envVar)
  if ([string]::IsNullOrWhiteSpace($token) -and $env:SKYBRIDGE_WORKER_TOKEN) { $token = $env:SKYBRIDGE_WORKER_TOKEN }
  $tokenFile = if ($Config.token_file) { [string]$Config.token_file } else { $env:SKYBRIDGE_WORKER_TOKEN_FILE }
  if ([string]::IsNullOrWhiteSpace($token) -and -not [string]::IsNullOrWhiteSpace($tokenFile)) {
    if (Test-Path -LiteralPath $tokenFile -PathType Leaf) {
      $token = (Get-Content -Raw -LiteralPath $tokenFile).Trim()
    }
  }
  if ([string]::IsNullOrWhiteSpace($token)) { return $null }
  return $token
}

function Test-SkyBridgeLocalApiBase {
  param([string]$ApiBase)
  try {
    $uri = [System.Uri]::new($ApiBase)
    return $uri.Host -in @("127.0.0.1", "localhost", "::1")
  } catch {
    return $false
  }
}

function Test-SkyBridgeHttpsApiBase {
  param([string]$ApiBase)
  try {
    return ([System.Uri]::new($ApiBase)).Scheme -eq "https"
  } catch {
    return $false
  }
}

function Assert-SkyBridgeWorkerApiSafety {
  param($Config)
  if ([string]::IsNullOrWhiteSpace([string]$Config.api_base)) {
    throw "SkyBridge api_base is required. Set skybridge_api_base in the worker profile or SKYBRIDGE_API_BASE."
  }
  $isLocal = Test-SkyBridgeLocalApiBase -ApiBase $Config.api_base
  if (-not $isLocal -and $Config.reject_insecure_http_for_remote -ne $false -and -not (Test-SkyBridgeHttpsApiBase -ApiBase $Config.api_base)) {
    throw "Remote SkyBridge api_base must use HTTPS unless reject_insecure_http_for_remote is explicitly false."
  }
  if (-not $isLocal -and $Config.allow_remote_server -ne $true) {
    throw "Worker profile api_base is remote, but allow_remote_server is not true."
  }
  if ($Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $Config))) {
    throw "SkyBridge worker token is required by auth_mode=bearer_token. Set the configured token env var or token_file."
  }
}

function Invoke-SkyBridgeApi {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST", "PATCH", "DELETE")][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    $Body = $null,
    [Parameter(Mandatory = $true)][string]$ApiBase,
    $Config = $null,
    [int]$TimeoutSeconds = 10
  )

  $uri = "$($ApiBase.TrimEnd('/'))$Path"
  $headers = @{}
  if ($Config -and [string]$Config.auth_mode -eq "bearer_token") {
    $token = Get-SkyBridgeWorkerToken -Config $Config
    if ([string]::IsNullOrWhiteSpace($token)) {
      throw "SkyBridge worker token is required by auth_mode=bearer_token. Set the configured token env var or token_file."
    }
    $headers["Authorization"] = "Bearer $token"
  }
  try {
    if ($null -eq $Body) {
      if ($Method -in @("POST", "PATCH")) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body "{}" -TimeoutSec $TimeoutSeconds
      }
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec $TimeoutSeconds
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
  } catch {
    $message = $_.Exception.Message
    $responseText = $null
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = [System.IO.StreamReader]::new($stream)
        $responseText = $reader.ReadToEnd()
      }
    } catch {}
    if ($responseText) { $message = "$message $responseText" }
    throw "SkyBridge API $Method $Path failed: $message"
  }
}

function Register-Worker {
  param($Config, [int]$TimeoutSeconds = 10)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/workers/register" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
    name = if ($Config.name) { $Config.name } else { $Config.worker_id }
    provider = "edge-worker"
    capabilities = @($Config.capabilities)
    labels = @("edge", "local", "windows")
    enabled = $true
    auth_mode = if ($Config.auth_mode) { [string]$Config.auth_mode } else { "none" }
    api_base = $Config.api_base
    allow_remote_server = [bool]$Config.allow_remote_server
  } -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Send-WorkerHeartbeat {
  param($Config, [string]$StatusNote = "ready", [double]$Load = 0, [int]$TimeoutSeconds = 10)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($Config.worker_id))/heartbeat" -ApiBase $Config.api_base -Body @{
    status_note = $StatusNote
    load = $Load
    seen_at = (Get-Date).ToUniversalTime().ToString("o")
  } -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Get-ProjectControlState {
  param($Config)
  Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($Config.project_id))/control" -ApiBase $Config.api_base -Config $Config
}

function Set-ProjectControlState {
  param($Config, [hashtable]$Patch)
  Invoke-SkyBridgeApi -Method PATCH -Path "/v1/projects/$([uri]::EscapeDataString($Config.project_id))/control" -ApiBase $Config.api_base -Body $Patch -Config $Config
}

function Test-SkyBridgeServerAvailable {
  param($Config)
  try {
    Invoke-SkyBridgeApi -Method GET -Path "/v1/health" -ApiBase $Config.api_base -TimeoutSeconds 5 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Get-QueuedTasks {
  param($Config)
  Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?status=queued&project_id=$([uri]::EscapeDataString($Config.project_id))" -ApiBase $Config.api_base -Config $Config
}

function Get-TaskType {
  param($Task)
  if ($Task -and -not [string]::IsNullOrWhiteSpace([string]$Task.task_type)) {
    return [string]$Task.task_type
  }
  $text = @($Task.title, $Task.prompt_summary, $Task.body, (@($Task.required_capabilities) -join " ")) -join " "
  if ($text -match "(?i)\bdocs?\b|documentation|readme") { return "docs" }
  if ($text -match "(?i)\btest\b|typecheck|lint|validation") { return "test" }
  if ($text -match "(?i)\bdeploy|production|secret|credential|github settings\b") { return "blocked" }
  return "code"
}

function Get-SkyBridgeTaskFiles {
  param($Task)
  $files = @()
  if ($Task.expected_files) { $files += @($Task.expected_files) }
  if ($Task.allowed_paths) { $files += @($Task.allowed_paths) }
  $files | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Test-SkyBridgeSafeLocalSmokeTask {
  param($Task)
  $files = @(Get-SkyBridgeTaskFiles -Task $Task)
  if ($files.Count -lt 1) { return $false }
  if (@($files | Where-Object { $_ -like "scripts/powershell/smoke-*.ps1" }).Count -ne $files.Count) { return $false }
  $text = (@($Task.title, $Task.body, $Task.prompt_summary, @($files)) -join " ")
  return ($text -notmatch "(?i)(production deploy|docker compose up|docker compose down|docker daemon|write secrets?|token file|private key|github settings|branch protection|server root|openresty|authelia|1panel|/opt/skybridge-agent-hub)")
}

function Normalize-SkyBridgeTaskCapabilities {
  param($Task)
  $original = @($Task.required_capabilities | ForEach-Object {
    $capability = ([string]$_).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($capability)) { $capability }
  } | Select-Object -Unique)
  $taskType = (Get-TaskType -Task $Task).ToLowerInvariant()
  $files = @(Get-SkyBridgeTaskFiles -Task $Task)
  $docsOnly = $files.Count -gt 0 -and @($files | Where-Object { $_ -like "docs/*" }).Count -eq $files.Count
  $safeSmokeOnly = Test-SkyBridgeSafeLocalSmokeTask -Task $Task
  $normalized = @($original)
  $reason = $null

  if ($taskType -eq "docs" -and $docsOnly) {
    $normalized = @($normalized | Where-Object { $_ -ne "docs" -and $_ -ne "documentation" })
    foreach ($capability in @("codex", "git", "gh")) {
      if ($normalized -notcontains $capability) { $normalized += $capability }
    }
    $reason = "docs_expected_files_use_codex_git_gh"
  } elseif ($taskType -eq "local-smoke" -and $safeSmokeOnly) {
    $normalized = @($normalized | Where-Object { $_ -ne "smoke" -and $_ -ne "local-smoke" })
    foreach ($capability in @("codex", "powershell", "windows")) {
      if ($normalized -notcontains $capability) { $normalized += $capability }
    }
    $reason = "safe_local_smoke_expected_files_use_codex_powershell_windows"
  }

  [pscustomobject]@{
    original_required_capabilities = @($original)
    normalized_required_capabilities = @($normalized | Select-Object -Unique)
    capability_normalization_reason = $reason
    task_type = $taskType
    expected_files = @($files)
    safe_local_smoke = [bool]$safeSmokeOnly
  }
}

function Test-TaskCompatible {
  param($Task, $Config)
  $workerCapabilities = @($Config.capabilities | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
  $capabilityPlan = Normalize-SkyBridgeTaskCapabilities -Task $Task
  $required = @($capabilityPlan.normalized_required_capabilities)
  $missing = @($required | Where-Object { $workerCapabilities -notcontains $_ })
  $rawMissing = @($capabilityPlan.original_required_capabilities | Where-Object { $_ -notin @("docs", "documentation", "smoke", "local-smoke") -and $workerCapabilities -notcontains $_ })
  $taskType = $capabilityPlan.task_type
  if (@($Config.blocked_task_types) -contains $taskType -or $taskType -eq "blocked") {
    return @{ compatible = $false; reason = "blocked_task_type:$taskType"; blocked_reason = "blocked_task_type:$taskType"; task_type = $taskType; original_required_capabilities = @($capabilityPlan.original_required_capabilities); normalized_required_capabilities = @($required); missing_raw_capabilities = @($rawMissing); missing_normalized_capabilities = @($missing); expected_files = @($capabilityPlan.expected_files) }
  }
  if (@($Config.allowed_task_types).Count -gt 0 -and @($Config.allowed_task_types) -notcontains $taskType) {
    return @{ compatible = $false; reason = "task_type_not_allowed:$taskType"; blocked_reason = "task_type_not_allowed:$taskType"; task_type = $taskType; original_required_capabilities = @($capabilityPlan.original_required_capabilities); normalized_required_capabilities = @($required); missing_raw_capabilities = @($rawMissing); missing_normalized_capabilities = @($missing); expected_files = @($capabilityPlan.expected_files) }
  }
  if ($taskType -eq "local-smoke" -and -not $capabilityPlan.safe_local_smoke) {
    return @{ compatible = $false; reason = "unsafe_local_smoke"; blocked_reason = "unsafe_local_smoke"; task_type = $taskType; original_required_capabilities = @($capabilityPlan.original_required_capabilities); normalized_required_capabilities = @($required); missing_raw_capabilities = @($rawMissing); missing_normalized_capabilities = @($missing); expected_files = @($capabilityPlan.expected_files) }
  }
  if ($missing.Count -gt 0) {
    return @{ compatible = $false; reason = "missing_capability:$($missing -join ',')"; task_type = $taskType; original_required_capabilities = @($capabilityPlan.original_required_capabilities); normalized_required_capabilities = @($required); missing_raw_capabilities = @($rawMissing); missing_normalized_capabilities = @($missing); blocked_reason = $null; expected_files = @($capabilityPlan.expected_files) }
  }
  return @{ compatible = $true; reason = "compatible"; task_type = $taskType; original_required_capabilities = @($capabilityPlan.original_required_capabilities); normalized_required_capabilities = @($required); missing_raw_capabilities = @($rawMissing); missing_normalized_capabilities = @(); blocked_reason = $null; capability_normalization_reason = $capabilityPlan.capability_normalization_reason; expected_files = @($capabilityPlan.expected_files) }
}

function Get-NextTask {
  param($Config, [string]$TaskId)
  $response = Get-QueuedTasks -Config $Config
  $tasks = @($response.tasks)
  if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
    $matches = @($tasks | Where-Object { $_.task_id -eq $TaskId })
    if ($matches.Count -lt 1) {
      return [pscustomobject]@{
        task = $null
        task_type = $null
        skipped = @([pscustomobject]@{
          task_id = $TaskId
          title = $null
          reason = "target_task_not_queued"
          task_type = $null
        })
      }
    }
    $tasks = $matches
  }
  $skipped = @()
  foreach ($task in @($tasks)) {
    $compatibility = Test-TaskCompatible -Task $task -Config $Config
    if ($compatibility.compatible) {
      return [pscustomobject]@{
        task = $task
        task_type = $compatibility.task_type
        skipped = $skipped
      }
    }
    $skipped += [pscustomobject]@{
      task_id = $task.task_id
      title = $task.title
      reason = $compatibility.reason
      blocked_reason = $compatibility.blocked_reason
      task_type = $compatibility.task_type
      expected_files = @($compatibility.expected_files)
      original_required_capabilities = @($compatibility.original_required_capabilities)
      normalized_required_capabilities = @($compatibility.normalized_required_capabilities)
      missing_raw_capabilities = @($compatibility.missing_raw_capabilities)
      missing_normalized_capabilities = @($compatibility.missing_normalized_capabilities)
    }
  }
  return [pscustomobject]@{ task = $null; task_type = $null; skipped = $skipped }
}

function Claim-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [int]$TimeoutSeconds = 10)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
  } -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Start-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [int]$TimeoutSeconds = 10)
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -ApiBase $Config.api_base -Body @{
    worker_id = $Config.worker_id
  } -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Complete-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{}, [int]$TimeoutSeconds = 10)
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -ApiBase $Config.api_base -Body $body -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Fail-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{}, [int]$TimeoutSeconds = 10)
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/fail" -ApiBase $Config.api_base -Body $body -Config $Config -TimeoutSeconds $TimeoutSeconds
}

function Block-Task {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{})
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/block" -ApiBase $Config.api_base -Body $body -Config $Config
}

function Repair-TaskEvidence {
  param($Config, [Parameter(Mandatory = $true)][string]$TaskId, [hashtable]$Result = @{})
  $body = @{ worker_id = $Config.worker_id }
  foreach ($key in $Result.Keys) { $body[$key] = $Result[$key] }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/evidence-repair" -ApiBase $Config.api_base -Body $body -Config $Config
}
