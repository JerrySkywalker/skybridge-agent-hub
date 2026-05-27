[CmdletBinding()]
param(
  [string]$ConfigFile,
  [string]$ProjectId,
  [switch]$AsEdgeWorkerConfig,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-DefaultWorkerProfilePath {
  $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Net.Dns]::GetHostName() }
  return (Join-Path $HOME ".skybridge\worker.$hostName.json")
}

function Resolve-WorkerProfilePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    if ($env:SKYBRIDGE_WORKER_PROFILE) { $Path = $env:SKYBRIDGE_WORKER_PROFILE }
    else { $Path = Get-DefaultWorkerProfilePath }
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Worker profile not found: $Path. Provide -ConfigFile or create the default profile under `$HOME\.skybridge."
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-StringField {
  param($Profile, [string]$Name)
  if ([string]::IsNullOrWhiteSpace([string]$Profile.$Name)) {
    throw "Worker profile missing required field '$Name'."
  }
}

function Assert-StringArrayField {
  param($Profile, [string]$Name)
  if (-not $Profile.$Name -or @($Profile.$Name).Count -eq 0) {
    throw "Worker profile field '$Name' must contain at least one value."
  }
  foreach ($value in @($Profile.$Name)) {
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
      throw "Worker profile field '$Name' contains an empty value."
    }
  }
}

function Read-WorkerProfile {
  param([string]$Path)
  $resolved = Resolve-WorkerProfilePath -Path $Path
  $profile = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json

  Assert-StringField -Profile $profile -Name "worker_id"
  Assert-StringField -Profile $profile -Name "display_name"
  Assert-StringArrayField -Profile $profile -Name "project_ids"
  if (-not $profile.allowed_project_ids) {
    $profile | Add-Member -NotePropertyName allowed_project_ids -NotePropertyValue @($profile.project_ids) -Force
  }
  Assert-StringArrayField -Profile $profile -Name "allowed_project_ids"
  Assert-StringArrayField -Profile $profile -Name "capabilities"
  Assert-StringArrayField -Profile $profile -Name "executor_adapters"
  if (-not $profile.repo_paths -or $profile.repo_paths.GetType().Name -notmatch "Object") {
    throw "Worker profile missing required object field 'repo_paths'."
  }
  if ([string]::IsNullOrWhiteSpace([string]$profile.skybridge_api_base)) {
    if ($env:SKYBRIDGE_API_BASE) {
      $profile | Add-Member -NotePropertyName skybridge_api_base -NotePropertyValue $env:SKYBRIDGE_API_BASE -Force
    } else {
      throw "Worker profile missing required field 'skybridge_api_base'."
    }
  }
  if ([string]$profile.auth_mode -eq "worker-token") {
    $profile.auth_mode = "bearer_token"
  }
  if ([string]::IsNullOrWhiteSpace([string]$profile.auth_mode)) {
    $profile | Add-Member -NotePropertyName auth_mode -NotePropertyValue "none" -Force
  }
  if (@("none", "bearer_token") -notcontains [string]$profile.auth_mode) {
    throw "Worker profile auth_mode must be one of: none, bearer_token."
  }
  if ([string]::IsNullOrWhiteSpace([string]$profile.token_env_var)) {
    $profile | Add-Member -NotePropertyName token_env_var -NotePropertyValue "SKYBRIDGE_WORKER_TOKEN" -Force
  }
  if ($null -eq $profile.allow_remote_server) { $profile | Add-Member -NotePropertyName allow_remote_server -NotePropertyValue $false -Force }
  if ($null -eq $profile.reject_insecure_http_for_remote) { $profile | Add-Member -NotePropertyName reject_insecure_http_for_remote -NotePropertyValue $true -Force }
  if ($null -eq $profile.allow_auto_merge) { $profile | Add-Member -NotePropertyName allow_auto_merge -NotePropertyValue $false -Force }
  if ($null -eq $profile.allow_production_deploy) { $profile | Add-Member -NotePropertyName allow_production_deploy -NotePropertyValue $false -Force }
  if ($profile.allow_production_deploy -eq $true) { throw "Worker profile cannot enable allow_production_deploy in this repository workflow." }
  if (-not $profile.max_parallel_tasks) { $profile | Add-Member -NotePropertyName max_parallel_tasks -NotePropertyValue 1 -Force }
  if ([int]$profile.max_parallel_tasks -gt 1) { throw "Worker profile max_parallel_tasks must be 1 until explicit locking exists." }
  if ([string]::IsNullOrWhiteSpace([string]$profile.codex_sandbox)) {
    $profile | Add-Member -NotePropertyName codex_sandbox -NotePropertyValue "workspace-write" -Force
  }
  return $profile
}

function ConvertTo-EdgeWorkerConfig {
  param($Profile, [string]$ProjectId)
  $selectedProject = if (-not [string]::IsNullOrWhiteSpace($ProjectId)) { $ProjectId } else { [string]@($Profile.project_ids)[0] }
  if (@($Profile.allowed_project_ids) -notcontains $selectedProject) {
    throw "Worker profile does not allow project '$selectedProject'."
  }
  $repoPath = $Profile.repo_paths.$selectedProject
  if ([string]::IsNullOrWhiteSpace([string]$repoPath)) {
    throw "Worker profile repo_paths does not define project '$selectedProject'."
  }
  [pscustomobject]@{
    worker_id = $Profile.worker_id
    name = $Profile.display_name
    project_id = $selectedProject
    repo_path = [string]$repoPath
    api_base = $Profile.skybridge_api_base
    auth_mode = $Profile.auth_mode
    token_env_var = $Profile.token_env_var
    token_file = $Profile.token_file
    allow_remote_server = [bool]$Profile.allow_remote_server
    reject_insecure_http_for_remote = [bool]$Profile.reject_insecure_http_for_remote
    capabilities = @($Profile.capabilities)
    executor_adapters = @($Profile.executor_adapters)
    allowed_task_types = @($Profile.preferred_task_types)
    blocked_task_types = @($Profile.blocked_task_types)
    max_parallel_tasks = [int]$Profile.max_parallel_tasks
    auto_merge_enabled = [bool]$Profile.allow_auto_merge
    allow_production_deploy = [bool]$Profile.allow_production_deploy
    codex_command = $Profile.codex_command
    codex_sandbox = $Profile.codex_sandbox
    codex_transport_max_retries = 1
    poll_interval_seconds = if ($Profile.poll_interval_seconds) { [int]$Profile.poll_interval_seconds } else { 30 }
    max_task_runtime_minutes = if ($Profile.max_task_runtime_minutes) { [int]$Profile.max_task_runtime_minutes } else { 30 }
    notification_enabled = if ($Profile.notification_enabled) { [bool]$Profile.notification_enabled } else { $false }
    profile_loaded = $true
  }
}

function Write-WorkerProfileResult {
  param($Result)
  if ($Json) { $Result | ConvertTo-Json -Depth 20 -Compress }
  else { $Result | Format-List }
}

if ($MyInvocation.InvocationName -ne ".") {
  $profile = Read-WorkerProfile -Path $ConfigFile
  if ($AsEdgeWorkerConfig) {
    Write-WorkerProfileResult (ConvertTo-EdgeWorkerConfig -Profile $profile -ProjectId $ProjectId)
  } else {
    Write-WorkerProfileResult @{
      ok = $true
      worker_id = $profile.worker_id
      display_name = $profile.display_name
      project_ids = @($profile.project_ids)
      allowed_project_ids = @($profile.allowed_project_ids)
      capabilities = @($profile.capabilities)
      executor_adapters = @($profile.executor_adapters)
      max_parallel_tasks = [int]$profile.max_parallel_tasks
      allow_auto_merge = [bool]$profile.allow_auto_merge
      allow_production_deploy = [bool]$profile.allow_production_deploy
      skybridge_api_base = $profile.skybridge_api_base
      auth_mode = $profile.auth_mode
      token_env_var = $profile.token_env_var
      token_file_configured = -not [string]::IsNullOrWhiteSpace([string]$profile.token_file)
      allow_remote_server = [bool]$profile.allow_remote_server
      reject_insecure_http_for_remote = [bool]$profile.reject_insecure_http_for_remote
      token_value_printed = $false
    }
  }
}
