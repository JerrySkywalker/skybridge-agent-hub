[CmdletBinding(DefaultParameterSetName = "Preview")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [Parameter(ParameterSetName = "Preview")][switch]$Preview,
  [Parameter(ParameterSetName = "Apply")][switch]$Apply,
  [string]$Confirm,
  [int]$Count = 2,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureStateDir
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$Mode = if ($Apply) { "apply" } else { "preview" }
$ConfirmText = "I_UNDERSTAND_SEED_BOUNDED_RUN_UNTIL_HOLD_PILOT_TASKS"
$MaxCount = 3
if ($Count -lt 1) { $Count = 1 }
if ($Count -gt $MaxCount) { $Count = $MaxCount }

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

function Get-PilotSpec {
  1..$Count | ForEach-Object {
    $suffix = "{0:D3}" -f $_
    [pscustomobject]@{
      task_id = "run-until-hold-pilot-docs-$suffix"
      allowed_path = "docs/operations/RUN_UNTIL_HOLD_PILOT_$suffix.md"
    }
  }
}

function New-PilotTask {
  param($Spec)
  [pscustomobject]@{
    task_id = $Spec.task_id
    project_id = $ProjectId
    title = "Goal 321 bounded run-until-hold pilot $($Spec.task_id)"
    body = "Create or update only $($Spec.allowed_path) for the bounded run-until-hold pilot."
    prompt_summary = "Docs-only bounded-loop pilot limited to $($Spec.allowed_path)."
    status = "queued"
    risk = "low"
    source = "manual"
    task_type = "docs"
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($Spec.allowed_path)
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".github/settings/**", "/opt/skybridge-agent-hub/**")
    validation = @("corepack pnpm smoke:run-until-hold-bounded")
    hygiene_metadata = [pscustomobject]@{
      goal = "mega-goal-321"
      bounded_loop_pilot = $true
      safe_start_one_pilot = $false
      old_residue = $false
      excluded_from_requeue = $false
      no_secrets = $true
      no_deploy = $true
      no_server_root = $true
      no_external_infrastructure = $true
      allowed_worker_id = "jerry-win-local-01"
    }
    selected_worker_id = "jerry-win-local-01"
    token_printed = $false
  }
}

function Test-SafePilotTask {
  param($Task, $Spec)
  if ($null -eq $Task) { return $false }
  $allowed = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $text = (@(
    Get-Prop -Object $Task -Name "title" -Default ""
    Get-Prop -Object $Task -Name "body" -Default ""
    Get-Prop -Object $Task -Name "prompt_summary" -Default ""
    @($allowed) -join " "
  ) -join " ").ToLowerInvariant()
  return (
    [string](Get-Prop -Object $Task -Name "task_id") -eq $Spec.task_id -and
    [string](Get-Prop -Object $Task -Name "project_id") -eq $ProjectId -and
    [string](Get-Prop -Object $Task -Name "status" -Default "queued") -in @("queued", "completed") -and
    [string](Get-Prop -Object $Task -Name "risk" -Default "") -eq "low" -and
    [string](Get-Prop -Object $Task -Name "task_type" -Default "") -in @("docs", "test") -and
    $allowed.Count -eq 1 -and $allowed[0] -eq $Spec.allowed_path -and
    [bool](Get-Prop -Object $metadata -Name "bounded_loop_pilot" -Default $false) -and
    $text -notmatch "(deploy|production|secret|credential|cookie|server-root|openresty|authelia|cloudflare|dns|github settings|branch protection|/opt/skybridge-agent-hub)"
  )
}

function Get-ExistingTasks {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
  } catch {
    return @()
  }
}

$specs = @(Get-PilotSpec)
$existing = @(Get-ExistingTasks)
$created = @()
$wouldCreate = @()
$blockers = [System.Collections.Generic.List[string]]::new()

foreach ($spec in $specs) {
  $match = @($existing | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $spec.task_id } | Select-Object -First 1)
  if ($match.Count -gt 0) {
    if (-not (Test-SafePilotTask -Task $match[0] -Spec $spec)) {
      $blockers.Add("existing_pilot_task_not_safe:$($spec.task_id)") | Out-Null
    } else {
      $created += [pscustomobject]@{
        task_id = $spec.task_id
        status = "existing_safe_pilot_task"
        task_status = [string](Get-Prop -Object $match[0] -Name "status" -Default "queued")
        allowed_paths = @($spec.allowed_path)
      }
    }
  } else {
    $wouldCreate += $spec
  }
}

if ($Mode -eq "apply" -and $Confirm -ne $ConfirmText) {
  $blockers.Add("confirmation_required") | Out-Null
} elseif ($Mode -eq "apply" -and $blockers.Count -eq 0) {
  $newTasks = @($wouldCreate | ForEach-Object { New-PilotTask -Spec $_ })
  if ($FixtureStateDir) {
    New-Item -ItemType Directory -Force -Path $FixtureStateDir | Out-Null
    [pscustomobject]@{ tasks = @($existing + $newTasks) } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $FixtureStateDir "seeded-tasks.json") -Encoding UTF8
  } elseif ($newTasks.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($ApiBase)) { throw "ApiBase is required for live apply." }
    $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
    foreach ($task in $newTasks) {
      Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks" -ApiBase $ApiBase -Body $task -Config $config -TimeoutSeconds $TimeoutSeconds | Out-Null
    }
  }
  foreach ($task in $newTasks) {
    $created += [pscustomobject]@{
      task_id = $task.task_id
      status = "created_safe_pilot_task"
      task_status = "queued"
      allowed_paths = @($task.allowed_paths)
    }
  }
}

$report = [pscustomobject]@{
  schema = "skybridge.run_until_hold_pilot_seed.v1"
  ok = ($blockers.Count -eq 0)
  mode = $Mode
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  count = $Count
  max_count = $MaxCount
  would_create = @($wouldCreate | ForEach-Object { [pscustomobject]@{ task_id = $_.task_id; allowed_paths = @($_.allowed_path) } })
  created_tasks = @($created)
  blockers = @($blockers.ToArray())
  safety = [pscustomobject]@{
    preview_default = $true
    apply_requires_exact_confirmation = $true
    deterministic_goal_321_tasks = $true
    docs_test_only = $true
    max_count_enforced = $true
    old_task_mutation = $false
    deploy_allowed = $false
    secrets_allowed = $false
    server_root_allowed = $false
    token_printed = $false
  }
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "OK:           $($report.ok)"
  "WouldCreate:  $(@($report.would_create).Count)"
  "Created:      $(@($report.created_tasks).Count)"
  "TokenPrinted: false"
}
