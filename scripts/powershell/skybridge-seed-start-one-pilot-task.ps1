[CmdletBinding(DefaultParameterSetName = "Preview")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [Parameter(ParameterSetName = "Preview")][switch]$Preview,
  [Parameter(ParameterSetName = "Apply")][switch]$Apply,
  [string]$Confirm,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureStateDir
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$PilotTaskId = "start-one-apply-pilot-docs-001"
$AllowedPath = "docs/operations/START_ONE_APPLY_PILOT.md"
$ConfirmText = "I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK"
$Mode = if ($Apply) { "apply" } else { "preview" }

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function New-PilotTask {
  [pscustomobject]@{
    task_id = $PilotTaskId
    project_id = $ProjectId
    title = "Goal 319 safe start-one apply pilot docs task"
    body = "Create or update the Goal 319 start-one apply pilot operations note only."
    prompt_summary = "Docs-only pilot limited to docs/operations/START_ONE_APPLY_PILOT.md."
    status = "queued"
    risk = "low"
    source = "manual"
    task_type = "docs"
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($AllowedPath)
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".github/settings/**", "/opt/skybridge-agent-hub/**")
    validation = @(
      "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1",
      "corepack pnpm smoke:start-one-apply-pilot"
    )
    hygiene_metadata = [pscustomobject]@{
      goal = "mega-goal-319"
      safe_start_one_pilot = $true
      old_residue = $false
      excluded_from_requeue = $false
      no_secrets = $true
      no_deploy = $true
      no_server_root = $true
      no_external_infrastructure = $true
      allowed_worker_id = "jerry-win-local-01"
    }
    token_printed = $false
  }
}

function Test-SafePilotTask {
  param($Task)
  if ($null -eq $Task) { return $false }
  $allowed = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  $required = @((Get-Prop -Object $Task -Name "required_capabilities" -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
  $combined = (@(
    Get-Prop -Object $Task -Name "title" -Default ""
    Get-Prop -Object $Task -Name "body" -Default ""
    Get-Prop -Object $Task -Name "prompt_summary" -Default ""
    @($allowed) -join " "
  ) -join " ").ToLowerInvariant()
  return (
    [string](Get-Prop -Object $Task -Name "task_id") -eq $PilotTaskId -and
    [string](Get-Prop -Object $Task -Name "project_id") -eq $ProjectId -and
    [string](Get-Prop -Object $Task -Name "status" -Default "queued") -in @("queued", "completed") -and
    [string](Get-Prop -Object $Task -Name "risk" -Default "") -eq "low" -and
    [string](Get-Prop -Object $Task -Name "task_type" -Default "") -eq "docs" -and
    $allowed.Count -eq 1 -and
    $allowed[0] -eq $AllowedPath -and
    $required -contains "codex" -and
    $required -contains "docs" -and
    $combined -notmatch "(deploy|production|secret|credential|cookie|server-root|openresty|authelia|cloudflare|dns|github settings|branch protection|/opt/skybridge-agent-hub)"
  )
}

function Get-ExistingTask {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $PilotTaskId } | Select-Object -First 1)
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return $null }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($PilotTaskId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return (Get-Prop -Object $response -Name "task" -Default $response)
  } catch {
    return $null
  }
}

function Write-FixtureTask {
  param($Task)
  if (-not $FixtureStateDir) { return }
  New-Item -ItemType Directory -Force -Path $FixtureStateDir | Out-Null
  $path = Join-Path $FixtureStateDir "seeded-task.json"
  [pscustomobject]@{ tasks = @($Task) } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

function New-Report {
  param(
    [bool]$Ok,
    [bool]$WouldCreate,
    $CreatedTask,
    [string[]]$Blockers = @(),
    [string]$Status = "preview_ready"
  )
  [pscustomobject]@{
    schema = "skybridge.start_one_pilot_seed.v1"
    ok = $Ok
    mode = $Mode
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    project_id = $ProjectId
    pilot_task_id = $PilotTaskId
    status = $Status
    would_create_task = $WouldCreate
    created_task = $CreatedTask
    blockers = @($Blockers)
    safety = [pscustomobject]@{
      preview_default = $true
      apply_requires_exact_confirmation = $true
      deterministic_task_id = $true
      docs_test_only = $true
      allowed_paths = @($AllowedPath)
      deploy_allowed = $false
      secrets_allowed = $false
      server_root_allowed = $false
      external_infrastructure_allowed = $false
      run_until_hold_called = $false
      project_control_unpaused = $false
      token_printed = $false
    }
    token_printed = $false
  }
}

$existing = Get-ExistingTask
if ($existing) {
  if (-not (Test-SafePilotTask -Task $existing)) {
    $report = New-Report -Ok $false -WouldCreate $false -CreatedTask $null -Blockers @("existing_pilot_task_not_safe") -Status "failed_closed"
  } else {
    $existingStatus = [string](Get-Prop -Object $existing -Name "status" -Default "queued")
    $reportStatus = if ($existingStatus -eq "completed") { "existing_completed_pilot_task" } else { "existing_safe_pilot_task" }
    $report = New-Report -Ok $true -WouldCreate $false -CreatedTask ([pscustomobject]@{ task_id = $PilotTaskId; status = $reportStatus; task_status = $existingStatus; allowed_paths = @($AllowedPath) }) -Status $reportStatus
  }
} elseif ($Mode -eq "preview") {
  $report = New-Report -Ok $true -WouldCreate $true -CreatedTask $null -Status "would_create_safe_pilot_task"
} else {
  if ($Confirm -ne $ConfirmText) {
    $report = New-Report -Ok $false -WouldCreate $true -CreatedTask $null -Blockers @("confirmation_required") -Status "failed_closed"
  } else {
    $task = New-PilotTask
    if ($FixtureStateDir) {
      Write-FixtureTask -Task $task
      $created = $task
    } else {
      if ([string]::IsNullOrWhiteSpace($ApiBase)) { throw "ApiBase is required for live apply." }
      $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
      $response = Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks" -ApiBase $ApiBase -Body $task -Config $config -TimeoutSeconds $TimeoutSeconds
      $created = Get-Prop -Object $response -Name "task" -Default $response
    }
    $report = New-Report -Ok $true -WouldCreate $false -CreatedTask ([pscustomobject]@{
      task_id = [string](Get-Prop -Object $created -Name "task_id" -Default $PilotTaskId)
      status = [string](Get-Prop -Object $created -Name "status" -Default "queued")
      risk = "low"
      task_type = "docs"
      allowed_paths = @($AllowedPath)
    }) -Status "created_safe_pilot_task"
  }
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "Status:       $($report.status)"
  "Task:         $($report.pilot_task_id)"
  "WouldCreate:  $($report.would_create_task)"
  "TokenPrinted: false"
}
