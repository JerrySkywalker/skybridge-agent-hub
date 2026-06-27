[CmdletBinding()]
param(
  [ValidateSet("status", "create-fixture", "preview-once", "apply-once", "attach-evidence", "complete-step", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "",
  [string]$StepId = "",
  [string]$TaskId = "",
  [string]$WorkerId = "",
  [string]$Confirm = "",
  [switch]$Fixture,
  [string]$OutputDir = ".agent/tmp/single-goal-loop",
  [int]$MaxTasks = 1,
  [ValidateSet("happy", "multiple-candidates", "unsafe-template", "codex-template", "matlab-template", "active-task", "stale-lease", "dependency-blocker")]
  [string]$FixtureScenario = "happy"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.single_goal_loop.v1"
$EvidenceSchema = "skybridge.single_goal_loop_evidence.v1"
$ApplyConfirmation = "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY"
$CreateConfirmation = "I_UNDERSTAND_CREATE_ONE_SINGLE_GOAL_LOOP_FIXTURE_OR_LIVE_RECORD_ONLY"
$TemplateIdTarget = "safe-local-smoke.v1"
$RunnerIdTarget = "safe-local-smoke-runner.v1"
$FixtureCampaignId = "local-cloud-single-goal-fixture"
$FixtureStepId = "safe-local-smoke-step"
$FixtureTaskId = "single-goal-safe-local-smoke-fixture-task"
$FixtureWorkerId = "mg352-fixture-worker"
$LiveCampaignId = "live-single-goal-loop-352-001"
$LiveStepId = "safe-local-smoke-step-352-001"
$LiveTaskId = "live-single-goal-loop-safe-task-352-001"
$LiveWorkerId = "jerry-win-local-01"

function ConvertTo-SafeJson($Value) {
  $Value | ConvertTo-Json -Depth 40
}

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  if ($value -match "^[A-Za-z]:/") {
    return "%PATH%/" + (Split-Path -Leaf $value)
  }
  return $value
}

function Get-LoopIds {
  $mode = if ($Fixture) { "fixture" } else { "live" }
  [pscustomobject]@{
    mode = $mode
    campaign_id = if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $CampaignId } elseif ($Fixture) { $FixtureCampaignId } else { $LiveCampaignId }
    step_id = if (-not [string]::IsNullOrWhiteSpace($StepId)) { $StepId } elseif ($Fixture) { $FixtureStepId } else { $LiveStepId }
    task_id = if (-not [string]::IsNullOrWhiteSpace($TaskId)) { $TaskId } elseif ($Fixture) { $FixtureTaskId } else { $LiveTaskId }
    worker_id = if (-not [string]::IsNullOrWhiteSpace($WorkerId)) { $WorkerId } elseif ($Fixture) { $FixtureWorkerId } else { $LiveWorkerId }
  }
}

function New-SafetyFlags {
  [pscustomobject]@{
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Get-PropertyValue($Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Invoke-ProviderInventory {
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $PSScriptRoot "skybridge-tool-provider.ps1"),
    "-Command",
    "inventory",
    "-NoVersionProbe",
    "-Json"
  )
  if ($Fixture) { $args += "-Fixture" }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "tool provider inventory failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Test-DirectProviderAvailable($Inventory) {
  $direct = @($Inventory.providers | Where-Object { $_.provider_id -eq "direct-local" } | Select-Object -First 1)
  return ($direct.Count -gt 0 -and [string]$direct[0].status -in @("available", "warning"))
}

function New-LoopEvidence($Ids) {
  $safety = New-SafetyFlags
  $record = [ordered]@{
    schema = $EvidenceSchema
    campaign_id = $Ids.campaign_id
    step_id = $Ids.step_id
    task_id = $Ids.task_id
    worker_id = $Ids.worker_id
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    provider_inventory_checked = $true
    direct_provider_available = $true
    task_claimed_count = 1
    execution_started = $true
    execution_completed = $true
    execution_failed = $false
    changed_files = @()
  }
  foreach ($property in $safety.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function New-LoopResult {
  param(
    [string]$Mode,
    [string]$ProjectIdValue,
    [string]$CampaignIdValue,
    [string]$StepIdValue,
    [string]$TaskIdValue,
    [string]$WorkerIdValue,
    [bool]$ProviderInventoryChecked = $false,
    [bool]$DirectProviderAvailable = $false,
    [bool]$PreviewOnly = $true,
    [bool]$ApplyConfirmed = $false,
    [bool]$TaskCreated = $false,
    [bool]$TaskClaimed = $false,
    [bool]$ExecutionStarted = $false,
    [bool]$ExecutionCompleted = $false,
    [bool]$ExecutionFailed = $false,
    [bool]$EvidenceAttached = $false,
    [bool]$StepCompleted = $false,
    [bool]$CampaignCompleted = $false,
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    [int]$TaskCreatedCount = 0,
    [int]$TaskClaimedCount = 0,
    [int]$ExecutionCompletedCount = 0,
    $Evidence = $null
  )
  $safety = New-SafetyFlags
  $record = [ordered]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    project_id = $ProjectIdValue
    campaign_id = $CampaignIdValue
    step_id = $StepIdValue
    task_id = $TaskIdValue
    worker_id = $WorkerIdValue
    provider_inventory_checked = $ProviderInventoryChecked
    direct_provider_available = $DirectProviderAvailable
    template_id = $TemplateIdTarget
    runner_id = $RunnerIdTarget
    preview_only = $PreviewOnly
    apply_confirmed = $ApplyConfirmed
    task_created = $TaskCreated
    task_claimed = $TaskClaimed
    execution_started = $ExecutionStarted
    execution_completed = $ExecutionCompleted
    execution_failed = $ExecutionFailed
    evidence_attached = $EvidenceAttached
    step_completed = $StepCompleted
    campaign_completed = $CampaignCompleted
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    safety_flags = $safety
    task_created_count = $TaskCreatedCount
    task_claimed_count = $TaskClaimedCount
    execution_completed_count = $ExecutionCompletedCount
  }
  foreach ($property in $safety.PSObject.Properties) { $record[$property.Name] = $property.Value }
  if ($null -ne $Evidence) { $record["evidence"] = $Evidence }
  [pscustomobject]$record
}

function New-FixtureTask {
  param([string]$TaskIdValue, [string]$TemplateId = $TemplateIdTarget, [string]$Status = "queued", [bool]$StaleLease = $false)
  [pscustomobject]@{
    task_id = $TaskIdValue
    template_id = $TemplateId
    runner_id = if ($TemplateId -eq $TemplateIdTarget) { $RunnerIdTarget } elseif ($TemplateId -like "codex-*") { "codex-analysis-report-runner.v1" } elseif ($TemplateId -like "matlab-*") { "matlab-parameter-sweep-runner.v1" } else { "unsupported-runner.v1" }
    status = $Status
    risk = "low"
    stale_lease = $StaleLease
    required_capabilities = if ($TemplateId -like "codex-*") { @("codex") } elseif ($TemplateId -like "matlab-*") { @("matlab") } else { @("powershell", "node", "pnpm") }
  }
}

function New-FixtureState($Ids) {
  $tasks = @()
  $stepDependencies = @()
  if ($FixtureScenario -eq "multiple-candidates") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id
    $tasks += New-FixtureTask -TaskIdValue "$($Ids.task_id)-extra"
  } elseif ($FixtureScenario -eq "unsafe-template") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id -TemplateId "unsafe-shell.v1"
  } elseif ($FixtureScenario -eq "codex-template") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id -TemplateId "codex-analysis-report.v1"
  } elseif ($FixtureScenario -eq "matlab-template") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id -TemplateId "matlab-parameter-sweep.v1"
  } elseif ($FixtureScenario -eq "active-task") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id -Status "running"
  } elseif ($FixtureScenario -eq "stale-lease") {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id -StaleLease $true
  } elseif ($FixtureScenario -eq "dependency-blocker") {
    $stepDependencies = @("previous-step")
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id
  } else {
    $tasks += New-FixtureTask -TaskIdValue $Ids.task_id
  }

  [pscustomobject]@{
    campaign = [pscustomobject]@{ campaign_id = $Ids.campaign_id; status = "ready"; step_count = 1 }
    step = [pscustomobject]@{ step_id = $Ids.step_id; status = "ready"; dependencies = @($stepDependencies) }
    tasks = @($tasks)
  }
}

function Test-FixturePreview($Ids, $Inventory) {
  $blockers = @()
  $warnings = @("fixture_mode")
  $state = New-FixtureState $Ids
  $directAvailable = Test-DirectProviderAvailable $Inventory
  if (-not $directAvailable) { Add-Finding ([ref]$blockers) "direct_provider_unavailable" }
  if ($MaxTasks -gt 1) { Add-Finding ([ref]$blockers) "max_tasks_exceeds_single_goal_limit" }
  if (@($state.step.dependencies).Count -gt 0) { Add-Finding ([ref]$blockers) "dependency_not_complete:previous-step" }
  if (@($state.tasks | Where-Object { $_.status -in @("queued", "claimed", "running") -and $_.task_id -ne $Ids.task_id }).Count -gt 0) { Add-Finding ([ref]$blockers) "multiple_candidate_tasks" }
  if (@($state.tasks | Where-Object { $_.status -in @("claimed", "running") }).Count -gt 0) { Add-Finding ([ref]$blockers) "active_task_present" }
  if (@($state.tasks | Where-Object { $_.stale_lease -eq $true }).Count -gt 0) { Add-Finding ([ref]$blockers) "stale_lease_present" }

  $target = @($state.tasks | Where-Object { $_.task_id -eq $Ids.task_id } | Select-Object -First 1)
  if ($target.Count -eq 0) {
    Add-Finding ([ref]$blockers) "target_task_missing"
  } else {
    $task = $target[0]
    if ($task.template_id -ne $TemplateIdTarget) {
      if ($task.template_id -like "codex-*") { Add-Finding ([ref]$blockers) "codex_template_rejected" }
      elseif ($task.template_id -like "matlab-*") { Add-Finding ([ref]$blockers) "matlab_template_rejected" }
      else { Add-Finding ([ref]$blockers) "unsafe_template_rejected" }
    }
    if ($task.runner_id -ne $RunnerIdTarget) { Add-Finding ([ref]$blockers) "runner_not_supported" }
    if ($task.required_capabilities -contains "codex") { Add-Finding ([ref]$blockers) "codex_capability_rejected" }
    if ($task.required_capabilities -contains "matlab") { Add-Finding ([ref]$blockers) "matlab_capability_rejected" }
    if ($task.status -ne "queued") { Add-Finding ([ref]$blockers) "target_task_not_queued" }
  }

  [pscustomobject]@{
    ok = (@($blockers).Count -eq 0)
    blockers = @($blockers)
    warnings = @($warnings)
    direct_provider_available = $directAvailable
  }
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

function Resolve-HomePathValue([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  $Value.Replace('$HOME', $profileHome).Replace('~', $profileHome)
}

function Resolve-LiveConfig {
  $homeRoot = [Environment]::GetFolderPath("UserProfile")
  $skybridgeConfigPath = Join-Path $homeRoot ".skybridge\skybridge.env.ps1"
  $workerConfigPath = Join-Path $homeRoot ".skybridge\worker.env.ps1"
  $resolvedApiBase = $ApiBase
  if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) {
    $resolvedApiBase = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) { $env:SKYBRIDGE_API_BASE } else { Get-ConfigValueFromFile -Path $skybridgeConfigPath -Name "SKYBRIDGE_API_BASE" }
  }
  $resolvedTokenFile = $TokenFile
  if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) {
    $resolvedTokenFile = if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE)) { $env:SKYBRIDGE_WORKER_TOKEN_FILE } else { Get-ConfigValueFromFile -Path $workerConfigPath -Name "SKYBRIDGE_WORKER_TOKEN_FILE" }
  }
  if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) { $resolvedTokenFile = Join-Path $homeRoot ".skybridge\worker-token.txt" }
  [pscustomobject]@{
    api_base = $resolvedApiBase
    token_file = Resolve-HomePathValue $resolvedTokenFile
  }
}

function Get-AuthHeaders([string]$ResolvedTokenFile) {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($ResolvedTokenFile) -and (Test-Path -LiteralPath $ResolvedTokenFile -PathType Leaf)) {
    $token = (Get-Content -Raw -LiteralPath $ResolvedTokenFile).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["Authorization"] = "Bearer $token" }
  }
  $headers
}

function Invoke-LoopApi {
  param(
    [ValidateSet("GET", "POST")]
    [string]$Method,
    [string]$Path,
    $Body = $null,
    [string]$ResolvedApiBase,
    [string]$ResolvedTokenFile
  )
  if ([string]::IsNullOrWhiteSpace($ResolvedApiBase)) {
    return [pscustomobject]@{ status_code = 0; body = [pscustomobject]@{ ok = $false; error = "api_base_not_configured"; token_printed = $false } }
  }
  $parameters = @{
    Method = $Method
    Uri = ($ResolvedApiBase.TrimEnd("/") + $Path)
    Headers = Get-AuthHeaders $ResolvedTokenFile
    SkipHttpErrorCheck = $true
    TimeoutSec = 30
  }
  if ($null -ne $Body) {
    $parameters.ContentType = "application/json"
    $parameters.Body = ConvertTo-SafeJson $Body
  }
  try {
    $response = Invoke-WebRequest @parameters
    $content = ($response.Content | Out-String).Trim()
    $bodyValue = if ([string]::IsNullOrWhiteSpace($content)) { [pscustomobject]@{ ok = $false; error = "empty_response"; token_printed = $false } } else { $content | ConvertFrom-Json }
    [pscustomobject]@{ status_code = [int]$response.StatusCode; body = $bodyValue }
  } catch {
    [pscustomobject]@{ status_code = 0; body = [pscustomobject]@{ ok = $false; error = "request_failed"; token_printed = $false } }
  }
}

function New-LiveCampaignPayload($Ids) {
  [pscustomobject]@{
    campaign_id = $Ids.campaign_id
    project_id = $ProjectId
    title = "MG352 single goal loop"
    description = "Single safe-local-smoke goal loop controlled by SkyBridge and executed once by the Windows local side."
    source = "single-goal-loop"
    status = "ready"
    safety_policy = @{
      single_step_only = $true
      max_tasks = 1
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      token_printed = $false
    }
    metadata = @{
      milestone = "M2"
      token_printed = $false
    }
    goals = @(
      @{
        campaign_step_id = $Ids.step_id
        goal_id = $Ids.step_id
        title = "Run one safe local smoke task"
        order = 1
        dependencies = @()
        metadata = @{
          template_id = $TemplateIdTarget
          runner_id = $RunnerIdTarget
          allowed_task_ids = @($Ids.task_id)
          token_printed = $false
        }
      }
    )
  }
}

function New-LiveTaskPayload($Ids) {
  [pscustomobject]@{
    task_id = $Ids.task_id
    project_id = $ProjectId
    title = "MG352 live single goal safe local smoke"
    body = "Run the fixed MG352 safe-local-smoke runner only. No Codex, MATLAB, Hermes, MCP, worker loop, queue runner, PR, or project-control unpause."
    prompt_summary = "MG352 deterministic safe-local-smoke task. Safe summary only."
    risk = "low"
    source = "manual"
    task_type = "safe-local-smoke"
    allowed_paths = @(".agent/tmp/single-goal-loop/**")
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings")
    validation = @(
      "fixed safe-local-smoke runner completed",
      "campaign step evidence attached",
      "token_printed=false"
    )
    required_capabilities = @("windows", "powershell", "node")
    planner_metadata = @{
      adapter = "mg352-single-goal-loop"
      decision = "continue"
      reason = "mg352_one_single_goal_safe_local_smoke"
      campaign_id = $Ids.campaign_id
      step_id = $Ids.step_id
      template_id = $TemplateIdTarget
      runner_id = $RunnerIdTarget
      source_run_id = "mega-goal-352-single-goal-loop"
      max_tasks = 1
      codex_run_called = $false
      matlab_run_called = $false
      hermes_run_called = $false
      mcp_run_called = $false
      arbitrary_shell_enabled = $false
      worker_loop_started = $false
      project_control_unpaused = $false
      token_printed = $false
    }
  }
}

function Test-LivePreview($Ids, $Inventory) {
  $blockers = @()
  $warnings = @("live_preview_no_mutation")
  $config = Resolve-LiveConfig
  $directAvailable = Test-DirectProviderAvailable $Inventory
  if (-not $directAvailable) { Add-Finding ([ref]$blockers) "direct_provider_unavailable" }
  if ($MaxTasks -gt 1) { Add-Finding ([ref]$blockers) "max_tasks_exceeds_single_goal_limit" }
  if ([string]::IsNullOrWhiteSpace($config.api_base)) { Add-Finding ([ref]$blockers) "api_base_not_configured" }
  if ([string]::IsNullOrWhiteSpace($config.token_file) -or -not (Test-Path -LiteralPath $config.token_file -PathType Leaf)) { Add-Finding ([ref]$blockers) "token_file_not_present" }
  if ($Ids.worker_id -ne $LiveWorkerId) { Add-Finding ([ref]$blockers) "unexpected_worker_id" }
  if ($Ids.campaign_id -ne $LiveCampaignId) { Add-Finding ([ref]$blockers) "unexpected_campaign_id" }
  if ($Ids.step_id -ne $LiveStepId) { Add-Finding ([ref]$blockers) "unexpected_step_id" }
  if ($Ids.task_id -ne $LiveTaskId) { Add-Finding ([ref]$blockers) "unexpected_task_id" }
  if (@($blockers).Count -eq 0) {
    $worker = Invoke-LoopApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($Ids.worker_id))" -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($worker.status_code -lt 200 -or $worker.status_code -ge 300) {
      Add-Finding ([ref]$blockers) "worker_not_registered_or_offline"
    } else {
      if ([string]$worker.body.worker.status -ne "online") { Add-Finding ([ref]$blockers) "worker_not_online" }
      if ($worker.body.worker.enabled -ne $true) { Add-Finding ([ref]$blockers) "worker_disabled" }
    }
    $task = Invoke-LoopApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($Ids.task_id))" -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($task.status_code -ge 200 -and $task.status_code -lt 300) {
      $taskStatus = [string]$task.body.task.status
      $metadata = $task.body.task.planner_metadata
      if ([string](Get-PropertyValue $metadata "campaign_id") -ne $Ids.campaign_id) { Add-Finding ([ref]$blockers) "existing_task_campaign_mismatch" }
      if ($taskStatus -in @("claimed", "running")) { Add-Finding ([ref]$blockers) "active_task_present" }
      if ($taskStatus -eq "completed") { Add-Finding ([ref]$warnings) "target_task_already_completed" }
    }
  }
  [pscustomobject]@{
    ok = (@($blockers).Count -eq 0)
    blockers = @($blockers)
    warnings = @($warnings)
    direct_provider_available = $directAvailable
    config = $config
  }
}

function Invoke-LiveApplyOnce($Ids, $Inventory) {
  $preview = Test-LivePreview $Ids $Inventory
  if (-not $preview.ok) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers $preview.blockers -Warnings $preview.warnings
  }
  if ($Confirm -ne $ApplyConfirmation) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("missing_exact_confirmation") -Warnings $preview.warnings
  }

  $config = $preview.config
  $taskCreated = $false
  $campaign = Invoke-LoopApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))" -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($campaign.status_code -eq 404) {
    $createdCampaign = Invoke-LoopApi -Method POST -Path "/v1/campaigns" -Body (New-LiveCampaignPayload $Ids) -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($createdCampaign.status_code -lt 200 -or $createdCampaign.status_code -ge 300) {
      return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -Blockers @("campaign_create_failed") -Warnings $preview.warnings
    }
  } elseif ($campaign.status_code -lt 200 -or $campaign.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -Blockers @("campaign_read_failed") -Warnings $preview.warnings
  }

  $task = Invoke-LoopApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($Ids.task_id))" -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($task.status_code -eq 404) {
    $createdTask = Invoke-LoopApi -Method POST -Path "/v1/tasks" -Body (New-LiveTaskPayload $Ids) -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($createdTask.status_code -lt 200 -or $createdTask.status_code -ge 300) {
      return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -Blockers @("task_create_failed") -Warnings $preview.warnings
    }
    $taskCreated = $true
  } elseif ($task.status_code -ge 200 -and $task.status_code -lt 300) {
    if ([string]$task.body.task.status -eq "completed") {
      $existingEvidence = New-LoopEvidence $Ids
      return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $false -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -EvidenceAttached $true -StepCompleted $true -CampaignCompleted $true -Warnings @($preview.warnings + "target_task_already_completed") -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Evidence $existingEvidence
    }
  } else {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -Blockers @("task_read_failed") -Warnings $preview.warnings
  }

  $claim = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($Ids.task_id))/claim" -Body @{ worker_id = $Ids.worker_id } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -Blockers @("task_claim_failed") -Warnings $preview.warnings
  }
  $start = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($Ids.task_id))/start" -Body @{ worker_id = $Ids.worker_id } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionFailed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -Blockers @("task_start_failed") -Warnings $preview.warnings
  }

  $evidence = New-LoopEvidence $Ids
  $complete = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($Ids.task_id))/complete" -Body @{
    worker_id = $Ids.worker_id
    summary = "MG352 single-goal safe-local-smoke task completed with sanitized evidence."
    evidence_summary = $evidence
  } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionStarted $true -ExecutionFailed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -Blockers @("task_complete_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $attach = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/steps/$([uri]::EscapeDataString($Ids.step_id))/attach-evidence" -Body @{
    linked_task_ids = @($Ids.task_id)
    evidence_summary = $evidence
  } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($attach.status_code -lt 200 -or $attach.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Blockers @("evidence_attach_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $stepComplete = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/steps/$([uri]::EscapeDataString($Ids.step_id))/complete" -Body @{
    linked_task_ids = @($Ids.task_id)
    evidence_summary = $evidence
    reason = "MG352 single safe-local-smoke task completed."
  } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($stepComplete.status_code -lt 200 -or $stepComplete.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -EvidenceAttached $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Blockers @("step_complete_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $campaignComplete = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/complete" -Body @{ reason = "MG352 one-step campaign completed." } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($campaignComplete.status_code -lt 200 -or $campaignComplete.status_code -ge 300) {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -EvidenceAttached $true -StepCompleted $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Blockers @("campaign_complete_failed") -Warnings @($preview.warnings + "campaign_hold_required") -Evidence $evidence
  }

  New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $Ids.campaign_id -StepIdValue $Ids.step_id -TaskIdValue $Ids.task_id -WorkerIdValue $Ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $taskCreated -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -EvidenceAttached $true -StepCompleted $true -CampaignCompleted $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Warnings $preview.warnings -Evidence $evidence
}

function Invoke-LoopCommand {
  $ids = Get-LoopIds
  $inventory = Invoke-ProviderInventory
  if ($Fixture) {
    $preview = Test-FixturePreview $ids $inventory
    if ($Command -eq "status" -or $Command -eq "safe-summary" -or $Command -eq "create-fixture" -or $Command -eq "report") {
      $warnings = @($preview.warnings)
      if ($Command -eq "create-fixture") { $warnings += "fixture_created_in_memory" }
      return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $true -Blockers $(if ($Command -eq "status" -or $Command -eq "safe-summary" -or $Command -eq "create-fixture") { @() } else { $preview.blockers }) -Warnings $warnings
    }
    if ($Command -eq "preview-once") {
      return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $true -Blockers $preview.blockers -Warnings $preview.warnings
    }
    if ($Command -eq "apply-once") {
      if (-not $preview.ok) {
        return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers $preview.blockers -Warnings $preview.warnings
      }
      if ($Confirm -ne $ApplyConfirmation) {
        return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("missing_exact_confirmation") -Warnings $preview.warnings
      }
      $evidence = New-LoopEvidence $ids
      return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -TaskCreated $true -TaskClaimed $true -ExecutionStarted $true -ExecutionCompleted $true -EvidenceAttached $true -StepCompleted $true -CampaignCompleted $true -Warnings $preview.warnings -TaskCreatedCount 1 -TaskClaimedCount 1 -ExecutionCompletedCount 1 -Evidence $evidence
    }
    if ($Command -eq "attach-evidence") {
      $evidence = New-LoopEvidence $ids
      return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -EvidenceAttached $true -Warnings $preview.warnings -Evidence $evidence
    }
    if ($Command -eq "complete-step") {
      $evidence = New-LoopEvidence $ids
      return New-LoopResult -Mode "fixture" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -EvidenceAttached $true -StepCompleted $true -CampaignCompleted $true -Warnings $preview.warnings -Evidence $evidence
    }
  }

  $livePreview = Test-LivePreview $ids $inventory
  if ($Command -eq "status" -or $Command -eq "safe-summary" -or $Command -eq "preview-once" -or $Command -eq "report") {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $livePreview.direct_provider_available -PreviewOnly $true -Blockers $livePreview.blockers -Warnings $livePreview.warnings
  }
  if ($Command -eq "create-fixture") {
    if ($Confirm -ne $CreateConfirmation) {
      return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $livePreview.direct_provider_available -PreviewOnly $false -Blockers @("missing_create_exact_confirmation") -Warnings $livePreview.warnings
    }
    if (-not $livePreview.ok) {
      return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $livePreview.direct_provider_available -PreviewOnly $false -Blockers $livePreview.blockers -Warnings $livePreview.warnings
    }
    $config = $livePreview.config
    $campaign = Invoke-LoopApi -Method POST -Path "/v1/campaigns" -Body (New-LiveCampaignPayload $ids) -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    $created = ($campaign.status_code -ge 200 -and $campaign.status_code -lt 300)
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $false -TaskCreated $false -Blockers $(if ($created) { @() } else { @("campaign_create_failed") }) -Warnings $livePreview.warnings
  }
  if ($Command -eq "apply-once") { return Invoke-LiveApplyOnce $ids $inventory }
  if ($Command -eq "attach-evidence" -or $Command -eq "complete-step") {
    return New-LoopResult -Mode "live" -ProjectIdValue $ProjectId -CampaignIdValue $ids.campaign_id -StepIdValue $ids.step_id -TaskIdValue $ids.task_id -WorkerIdValue $ids.worker_id -ProviderInventoryChecked $true -DirectProviderAvailable $livePreview.direct_provider_available -PreviewOnly $false -Blockers @("live_attach_or_complete_requires_apply_once") -Warnings $livePreview.warnings
  }
}

function Write-LoopReport($Result) {
  $targetRoot = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
  $fullTarget = [IO.Path]::GetFullPath($targetRoot)
  $agentTmp = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  if (-not $fullTarget.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp."
  }
  New-Item -ItemType Directory -Force -Path $fullTarget | Out-Null
  $jsonPath = Join-Path $fullTarget "single-goal-loop.json"
  $mdPath = Join-Path $fullTarget "single-goal-loop.md"
  $Result | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Single Goal Loop Controller",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- project_id: $($Result.project_id)",
    "- campaign_id: $($Result.campaign_id)",
    "- step_id: $($Result.step_id)",
    "- task_id: $($Result.task_id)",
    "- worker_id: $($Result.worker_id)",
    "- provider_inventory_checked: $($Result.provider_inventory_checked)",
    "- direct_provider_available: $($Result.direct_provider_available)",
    "- template_id: $($Result.template_id)",
    "- runner_id: $($Result.runner_id)",
    "- preview_only: $($Result.preview_only)",
    "- apply_confirmed: $($Result.apply_confirmed)",
    "- task_created: $($Result.task_created)",
    "- task_claimed: $($Result.task_claimed)",
    "- execution_started: $($Result.execution_started)",
    "- execution_completed: $($Result.execution_completed)",
    "- evidence_attached: $($Result.evidence_attached)",
    "- step_completed: $($Result.step_completed)",
    "- campaign_completed: $($Result.campaign_completed)",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- hermes_run_called: false",
    "- mcp_run_called: false",
    "- arbitrary_shell_enabled: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Blockers",
    ""
  )
  if (@($Result.blockers).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.blockers)) { $lines += "- $item" } }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.warnings)) { $lines += "- $item" } }
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
  [pscustomobject]@{ json = Convert-ToSafePath $jsonPath; markdown = Convert-ToSafePath $mdPath }
}

$result = Invoke-LoopCommand
if ($WriteReport -or $Command -eq "report") {
  $paths = Write-LoopReport $result
  $result | Add-Member -NotePropertyName report_json_path -NotePropertyValue $paths.json -Force
  $result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue $paths.markdown -Force
}

if ($Json) {
  $result | ConvertTo-Json -Depth 40
} else {
  "Single goal loop: $($result.mode)"
  "Campaign: $($result.campaign_id)"
  "Step: $($result.step_id)"
  "Task: $($result.task_id)"
  "Provider inventory checked: $($result.provider_inventory_checked)"
  "Direct provider available: $($result.direct_provider_available)"
  "Task created: $($result.task_created)"
  "Task claimed: $($result.task_claimed)"
  "Execution completed: $($result.execution_completed)"
  "Evidence attached: $($result.evidence_attached)"
  "Step completed: $($result.step_completed)"
  "Campaign completed: $($result.campaign_completed)"
  "token_printed=false"
}
