[CmdletBinding()]
param(
  [string]$ServiceName = "SkyBridgeWorkerService",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [string[]]$ForceMissingTool = @(),
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-SkyBridgeRepoRoot {
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    return (Resolve-Path -LiteralPath $RepoRoot).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-SkyBridgeHomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    return (Resolve-Path -LiteralPath $HomeRoot).Path
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
  return "."
}

function Test-SkyBridgeCommand {
  param([string]$Name)
  try { return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue) } catch { return $false }
}

function Test-SkyBridgeConfigKey {
  param([string]$Path, [string[]]$Keys)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $text = Get-Content -Raw -LiteralPath $Path
  foreach ($key in $Keys) {
    if ($text -match ("(?m)^\s*(?:`$env:)?{0}\s*=" -f [regex]::Escape($key))) { return $true }
  }
  return $false
}

function Read-SkyBridgeSafeConfigValue {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($text, ("(?m)^\s*(?:`$env:)?{0}\s*=\s*['""]?([^'""]+)" -f [regex]::Escape($Key)))
  if (-not $match.Success) { return $null }
  $value = $match.Groups[1].Value.Trim()
  if ($value -notmatch "^[A-Za-z0-9_.:@-]{1,80}$") { return $null }
  return $value
}

function Get-SkyBridgeServiceSnapshot {
  param([string]$Name)
  if (-not $IsWindows) {
    return [pscustomobject]@{
      service_installed = $false
      service_running = $false
      service_start_type = "unsupported_non_windows"
      warning = "windows_service_inspection_unavailable"
    }
  }

  try {
    $service = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name.Replace("'", "''")) -ErrorAction Stop
    if (-not $service) {
      return [pscustomobject]@{
        service_installed = $false
        service_running = $false
        service_start_type = "not_installed"
        warning = $null
      }
    }
    return [pscustomobject]@{
      service_installed = $true
      service_running = ([string]$service.State -eq "Running")
      service_start_type = if ([string]::IsNullOrWhiteSpace([string]$service.StartMode)) { "unknown" } else { [string]$service.StartMode }
      warning = $null
    }
  } catch {
    return [pscustomobject]@{
      service_installed = $false
      service_running = $false
      service_start_type = "unknown"
      warning = "service_inspection_failed"
    }
  }
}

$repo = Resolve-SkyBridgeRepoRoot
$homeRootPath = Resolve-SkyBridgeHomeRoot
$skybridgeConfig = Join-Path $homeRootPath ".skybridge\skybridge.env.ps1"
$workerConfig = Join-Path $homeRootPath ".skybridge\worker.env.ps1"
$workerToken = Join-Path $homeRootPath ".skybridge\worker-token.txt"

$repoRootDetected = (
  (Test-Path -LiteralPath (Join-Path $repo "package.json") -PathType Leaf) -and
  (Test-Path -LiteralPath (Join-Path $repo "AGENTS.md") -PathType Leaf)
)

$apiBaseConfigured = (
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE) -or
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_REMOTE_API_BASE) -or
  (Test-SkyBridgeConfigKey -Path $skybridgeConfig -Keys @("SKYBRIDGE_API_BASE", "SKYBRIDGE_REMOTE_API_BASE"))
)

$tokenFilePresent = (
  (Test-Path -LiteralPath $workerToken -PathType Leaf) -or
  (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE) -and (Test-Path -LiteralPath $env:SKYBRIDGE_WORKER_TOKEN_FILE -PathType Leaf))
)

$workerId = $env:SKYBRIDGE_WORKER_ID
if ([string]::IsNullOrWhiteSpace($workerId)) {
  $workerId = Read-SkyBridgeSafeConfigValue -Path $workerConfig -Key "SKYBRIDGE_WORKER_ID"
}
if ([string]::IsNullOrWhiteSpace($workerId)) { $workerId = "local-windows-worker" }

$tools = [ordered]@{
  powershell = $true
  git = Test-SkyBridgeCommand "git"
  gh = Test-SkyBridgeCommand "gh"
  node = Test-SkyBridgeCommand "node"
  pnpm = (Test-SkyBridgeCommand "pnpm") -or (Test-SkyBridgeCommand "corepack")
  codex = Test-SkyBridgeCommand "codex"
  matlab = (Test-SkyBridgeCommand "matlab") -or (Test-SkyBridgeCommand "matlab.exe")
}
foreach ($toolName in @($ForceMissingTool)) {
  $normalizedTool = ([string]$toolName).Trim().ToLowerInvariant()
  if (@($tools.Keys) -contains $normalizedTool) { $tools[$normalizedTool] = $false }
}

$service = Get-SkyBridgeServiceSnapshot -Name $ServiceName
$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not [bool]$service.service_installed) { $blockers.Add("service_not_installed") | Out-Null }
if ([bool]$service.service_installed -and -not [bool]$service.service_running) { $warnings.Add("service_installed_not_running") | Out-Null }
if (-not $apiBaseConfigured) { $blockers.Add("api_base_not_configured") | Out-Null }
if (-not $tokenFilePresent) { $blockers.Add("worker_token_file_missing") | Out-Null }
if (-not $repoRootDetected) { $blockers.Add("repo_root_not_detected") | Out-Null }
foreach ($requiredTool in @("powershell", "git", "node", "pnpm")) {
  if (-not [bool]$tools[$requiredTool]) { $blockers.Add("tool_missing_$requiredTool") | Out-Null }
}
if (-not [bool]$tools["gh"]) { $warnings.Add("gh_missing_pr_operations_disabled") | Out-Null }
if (-not [bool]$tools["codex"]) { $warnings.Add("codex_missing_codex_templates_disabled") | Out-Null }
if (-not [bool]$tools["matlab"]) { $warnings.Add("matlab_missing_matlab_templates_disabled") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace([string]$service.warning)) { $warnings.Add([string]$service.warning) | Out-Null }

$readinessStatus = if ($blockers.Count -gt 0) { "blocked" } elseif ($warnings.Count -gt 0) { "warning" } else { "ready" }
$recommended = if (-not [bool]$service.service_installed) {
  "run_install_preview"
} elseif (-not $apiBaseConfigured) {
  "create_skybridge_api_base_config"
} elseif (-not $tokenFilePresent) {
  "add_worker_token_file"
} elseif ($blockers.Count -gt 0) {
  "resolve_blockers"
} elseif ($warnings.Count -gt 0) {
  "review_capability_warnings"
} else {
  "ready_for_future_worker_loop_goal"
}

$report = [pscustomobject]@{
  schema = "skybridge.local_worker_service_status.v1"
  ok = $true
  worker_id = $workerId
  service_name = $ServiceName
  service_installed = [bool]$service.service_installed
  service_running = [bool]$service.service_running
  service_start_type = [string]$service.service_start_type
  install_state = if ([bool]$service.service_installed) { "installed" } else { "not_installed_preview_available" }
  repair_state = if ([bool]$service.service_installed) { "repair_preview_available" } else { "install_required_before_repair" }
  install_preview_available = $true
  repair_preview_available = $true
  api_base_configured = [bool]$apiBaseConfigured
  token_file_present = [bool]$tokenFilePresent
  repo_root_detected = [bool]$repoRootDetected
  powershell_available = [bool]$tools["powershell"]
  git_available = [bool]$tools["git"]
  gh_available = [bool]$tools["gh"]
  node_available = [bool]$tools["node"]
  pnpm_available = [bool]$tools["pnpm"]
  codex_available = [bool]$tools["codex"]
  matlab_available = [bool]$tools["matlab"]
  capabilities = [pscustomobject]@{
    status_readonly = $true
    install_preview = $true
    repair_preview = $true
    doctor_readonly = $true
    service_apply = $false
    task_claim = $false
    task_execute = $false
    worker_loop = $false
    codex_execution = $false
    matlab_execution = $false
    arbitrary_shell = $false
    tools = [pscustomobject]$tools
    token_printed = $false
  }
  readiness_status = $readinessStatus
  blockers = @($blockers)
  warnings = @($warnings)
  recommended_next_action = $recommended
  claim_enabled = $false
  execute_enabled = $false
  worker_loop_started = $false
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20 -Compress
} else {
  "Schema: $($report.schema)"
  "Worker: $($report.worker_id)"
  "Service: $($report.service_name)"
  "Installed: $($report.service_installed)"
  "Running: $($report.service_running)"
  "Readiness: $($report.readiness_status)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
