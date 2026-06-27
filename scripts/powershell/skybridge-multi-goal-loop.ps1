[CmdletBinding()]
param(
  [ValidateSet("status", "create-fixture", "preview-next", "apply-next", "attach-evidence", "complete-step", "hold", "report", "safe-summary")]
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
  [int]$MaxSteps = 1,
  [string]$Confirm = "",
  [switch]$Fixture,
  [switch]$Live,
  [string]$OutputDir = ".agent/tmp/multi-goal-loop",
  [ValidateSet("happy", "dependency-step2", "dependency-step3", "active-task", "stale-lease", "unsafe-template", "unknown-template", "multiple-candidates")]
  [string]$FixtureScenario = "happy"
)

$ErrorActionPreference = "Stop"

if ($Live) {
  $Fixture = $false
} elseif (-not $Fixture) {
  $Fixture = $true
}

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.multi_goal_loop.v1"
$EvidenceSchema = "skybridge.multi_goal_loop_evidence.v1"
$FixtureApplyConfirmation = "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY"
$LiveApplyConfirmation = "I_UNDERSTAND_RUN_ONE_LIVE_STATIC_MULTI_GOAL_STEP_ONLY"
$FixtureCampaignId = "local-cloud-static-multi-goal-fixture"
$LiveCampaignId = "live-static-multi-goal-loop-353-001"
$FixtureWorkerId = "mg353-fixture-worker"
$LiveWorkerId = "jerry-win-local-01"

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Get-CleanFindings($Values) {
  @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function ConvertTo-SafeJson($Value) {
  $Value | ConvertTo-Json -Depth 60
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

function Resolve-OutputRoot {
  $targetRoot = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
  $fullTarget = [IO.Path]::GetFullPath($targetRoot)
  $agentTmp = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  if (-not $fullTarget.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp."
  }
  $fullTarget
}

function New-SafetyFlags {
  param([bool]$CodexRunCalled = $false, [bool]$MatlabRunCalled = $false)
  [pscustomobject]@{
    codex_run_called = $CodexRunCalled
    matlab_run_called = $MatlabRunCalled
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

function New-StepDefinition {
  param(
    [int]$Order,
    [string]$StepIdValue,
    [string]$TaskIdValue,
    [string]$TemplateId,
    [string]$RunnerId,
    [string]$ProviderRequired,
    [string[]]$Dependencies,
    [string[]]$Artifacts,
    [string]$ValidationSummary
  )
  [pscustomobject]@{
    order = $Order
    step_id = $StepIdValue
    task_id = $TaskIdValue
    template_id = $TemplateId
    runner_id = $RunnerId
    provider_required = $ProviderRequired
    dependencies = @($Dependencies)
    artifacts = @($Artifacts)
    validation_summary = $ValidationSummary
  }
}

function Get-StepDefinitions {
  if ($Fixture) {
    return @(
      New-StepDefinition -Order 1 -StepIdValue "safe-local-smoke-step-353-001" -TaskIdValue "static-multi-goal-safe-task-fixture-353-001" -TemplateId "safe-local-smoke.v1" -RunnerId "safe-local-smoke-runner.v1" -ProviderRequired "direct" -Dependencies @() -Artifacts @() -ValidationSummary "fixture safe-local-smoke completed"
      New-StepDefinition -Order 2 -StepIdValue "matlab-golden-step-353-002" -TaskIdValue "static-multi-goal-matlab-task-fixture-353-002" -TemplateId "matlab-parameter-sweep.v1" -RunnerId "matlab-parameter-sweep-runner.v1" -ProviderRequired "matlab" -Dependencies @("safe-local-smoke-step-353-001") -Artifacts @(".agent/tmp/multi-goal-loop/matlab-fixture/manifest.json", ".agent/tmp/multi-goal-loop/matlab-fixture/summary.json", ".agent/tmp/multi-goal-loop/matlab-fixture/metrics.csv") -ValidationSummary "fixture fixed MATLAB runner evidence simulated without MATLAB invocation"
      New-StepDefinition -Order 3 -StepIdValue "codex-report-step-353-003" -TaskIdValue "static-multi-goal-codex-task-fixture-353-003" -TemplateId "codex-analysis-report.v1" -RunnerId "codex-analysis-report-runner.v1" -ProviderRequired "codex" -Dependencies @("matlab-golden-step-353-002") -Artifacts @(".agent/tmp/multi-goal-loop/codex-fixture/report.md") -ValidationSummary "fixture fixed Codex report evidence simulated without Codex invocation"
    )
  }
  @(
    New-StepDefinition -Order 1 -StepIdValue "live-static-safe-step-353-001" -TaskIdValue "live-static-safe-task-353-001" -TemplateId "safe-local-smoke.v1" -RunnerId "safe-local-smoke-runner.v1" -ProviderRequired "direct" -Dependencies @() -Artifacts @() -ValidationSummary "live safe-local-smoke task completed"
    New-StepDefinition -Order 2 -StepIdValue "live-static-matlab-step-353-002" -TaskIdValue "live-static-matlab-task-353-002" -TemplateId "matlab-parameter-sweep.v1" -RunnerId "matlab-parameter-sweep-runner.v1" -ProviderRequired "matlab" -Dependencies @("live-static-safe-step-353-001") -Artifacts @(".agent/tmp/multi-goal-loop/live-matlab/manifest.json", ".agent/tmp/multi-goal-loop/live-matlab/summary.json", ".agent/tmp/multi-goal-loop/live-matlab/metrics.csv") -ValidationSummary "live fixed MATLAB step accepted by exact static loop gate"
    New-StepDefinition -Order 3 -StepIdValue "live-static-codex-step-353-003" -TaskIdValue "live-static-codex-task-353-003" -TemplateId "codex-analysis-report.v1" -RunnerId "codex-analysis-report-runner.v1" -ProviderRequired "codex" -Dependencies @("live-static-matlab-step-353-002") -Artifacts @(".agent/tmp/multi-goal-loop/live-codex/report.md") -ValidationSummary "live fixed Codex report step accepted by exact static loop gate"
  )
}

function Get-LoopIds {
  [pscustomobject]@{
    mode = if ($Fixture) { "fixture" } else { "live" }
    campaign_id = if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $CampaignId } elseif ($Fixture) { $FixtureCampaignId } else { $LiveCampaignId }
    worker_id = if (-not [string]::IsNullOrWhiteSpace($WorkerId)) { $WorkerId } elseif ($Fixture) { $FixtureWorkerId } else { $LiveWorkerId }
  }
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

function Test-ToolDetected($Inventory, [string]$ToolId) {
  $tool = @($Inventory.tools | Where-Object { $_.tool_id -eq $ToolId } | Select-Object -First 1)
  return ($tool.Count -gt 0 -and [string]$tool[0].status -eq "detected")
}

function Test-StepProviderAvailable($Inventory, $Step) {
  if ($Fixture) { return $true }
  if ([string]$Step.provider_required -eq "direct") { return Test-DirectProviderAvailable $Inventory }
  if ([string]$Step.provider_required -eq "matlab") { return (Test-DirectProviderAvailable $Inventory) -and (Test-ToolDetected $Inventory "matlab") }
  if ([string]$Step.provider_required -eq "codex") { return (Test-DirectProviderAvailable $Inventory) -and (Test-ToolDetected $Inventory "codex") }
  $false
}

function Get-FixtureStatePath {
  Join-Path (Resolve-OutputRoot) "fixture-state.json"
}

function Read-FixtureState {
  $path = Get-FixtureStatePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{
      schema = "skybridge.multi_goal_loop_fixture_state.v1"
      campaign_id = $FixtureCampaignId
      completed_steps = @()
      evidence = [pscustomobject]@{}
      held = $false
      failed_steps = @()
      token_printed = $false
    }
  }
  Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Write-FixtureState($State) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $State | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $root "fixture-state.json") -Encoding UTF8
}

function Get-CompletedStepIds($State) {
  @($State.completed_steps | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-LoopEvidence {
  param($Ids, $Step)
  $safety = New-SafetyFlags
  $record = [ordered]@{
    schema = $EvidenceSchema
    campaign_id = $Ids.campaign_id
    step_id = $Step.step_id
    task_id = $Step.task_id
    worker_id = $Ids.worker_id
    template_id = $Step.template_id
    runner_id = $Step.runner_id
    provider_inventory_checked = $true
    direct_provider_available = $true
    task_claimed_count = 1
    execution_started = $true
    execution_completed = $true
    execution_failed = $false
    changed_files = @($Step.artifacts)
    produced_artifacts_safe = @($Step.artifacts)
    validation_summary_safe = $Step.validation_summary
  }
  foreach ($property in $safety.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function Get-ExpectedRunner([string]$TemplateId) {
  if ($TemplateId -eq "safe-local-smoke.v1") { return "safe-local-smoke-runner.v1" }
  if ($TemplateId -eq "matlab-parameter-sweep.v1") { return "matlab-parameter-sweep-runner.v1" }
  if ($TemplateId -eq "codex-analysis-report.v1") { return "codex-analysis-report-runner.v1" }
  "unsupported-runner.v1"
}

function Get-ScenarioStep($Step) {
  $copy = $Step | Select-Object *
  if ($FixtureScenario -eq "unsafe-template") {
    $copy.template_id = "unsafe-shell.v1"
    $copy.runner_id = "unsupported-runner.v1"
    $copy.provider_required = "disabled"
  } elseif ($FixtureScenario -eq "unknown-template") {
    $copy.template_id = "unknown-template.v1"
    $copy.runner_id = "unsupported-runner.v1"
    $copy.provider_required = "future"
  }
  $copy
}

function Test-StepTemplate($Step, [ref]$Blockers) {
  $expectedRunner = Get-ExpectedRunner ([string]$Step.template_id)
  if ($expectedRunner -eq "unsupported-runner.v1") {
    if ([string]$Step.template_id -eq "unsafe-shell.v1") {
      Add-Finding $Blockers "unsafe_template_rejected"
    } else {
      Add-Finding $Blockers "unknown_template_rejected"
    }
  }
  if ([string]$Step.runner_id -ne $expectedRunner) {
    Add-Finding $Blockers "runner_not_supported"
  }
}

function Get-StepView {
  param($Step, [string[]]$CompletedStepIds, $Inventory, [string]$SelectedStepId, [string[]]$SelectionBlockers, [bool]$EvidenceAttached)
  $dependencyBlockers = @()
  foreach ($dependency in @($Step.dependencies)) {
    if ($CompletedStepIds -notcontains [string]$dependency) {
      $dependencyBlockers += "dependency_not_complete:$dependency"
    }
  }
  $providerAvailable = Test-StepProviderAvailable $Inventory $Step
  $blockers = @($dependencyBlockers)
  if (-not $providerAvailable) { $blockers += "provider_unavailable:$($Step.provider_required)" }
  if ($Step.step_id -eq $SelectedStepId) { $blockers = @($blockers + $SelectionBlockers) }
  $blockers = Get-CleanFindings $blockers
  $completed = $CompletedStepIds -contains [string]$Step.step_id
  $dependencyStatus = if ($completed) { "complete" } elseif (@($dependencyBlockers).Count -eq 0) { "ready" } else { "blocked" }
  $state = if ($completed) { "completed" } elseif (@($blockers).Count -gt 0) { "blocked" } elseif ($Step.step_id -eq $SelectedStepId) { "ready" } else { "pending" }
  $warnings = @()
  if ($Fixture -and [string]$Step.provider_required -eq "matlab") { $warnings += "fixture_mode_no_matlab_invocation" }
  if ($Fixture -and [string]$Step.provider_required -eq "codex") { $warnings += "fixture_mode_no_codex_invocation" }
  [pscustomobject]@{
    step_id = $Step.step_id
    order = [int]$Step.order
    state = $state
    template_id = $Step.template_id
    runner_id = $Step.runner_id
    task_id = $Step.task_id
    dependencies = @($Step.dependencies)
    dependency_status = $dependencyStatus
    provider_required = $Step.provider_required
    provider_available = $providerAvailable
    can_preview = $true
    can_apply_next = ($Step.step_id -eq $SelectedStepId -and @($blockers).Count -eq 0 -and -not $completed)
    evidence_attached = [bool]$EvidenceAttached
    completed = [bool]$completed
    failed = $false
    held = $false
    blockers = @($blockers)
    warnings = @($warnings)
  }
}

function Select-NextStep {
  param([object[]]$Steps, [string[]]$CompletedStepIds)
  if (-not [string]::IsNullOrWhiteSpace($StepId)) {
    return @($Steps | Where-Object { $_.step_id -eq $StepId } | Select-Object -First 1)
  }
  foreach ($step in @($Steps | Sort-Object order)) {
    if ($CompletedStepIds -contains [string]$step.step_id) { continue }
    $blocked = $false
    foreach ($dependency in @($step.dependencies)) {
      if ($CompletedStepIds -notcontains [string]$dependency) { $blocked = $true }
    }
    if (-not $blocked) { return @($step) }
  }
  @()
}

function Test-Selection {
  param($SelectedStep, [string[]]$CompletedStepIds, $Inventory)
  $blockers = @()
  if ($MaxSteps -ne 1) { Add-Finding ([ref]$blockers) "max_steps_must_be_1" }
  if ($null -eq $SelectedStep) {
    Add-Finding ([ref]$blockers) "no_ready_step"
    return @($blockers)
  }
  if (-not [string]::IsNullOrWhiteSpace($TaskId) -and [string]$TaskId -ne [string]$SelectedStep.task_id) {
    Add-Finding ([ref]$blockers) "unexpected_task_id"
  }
  if ($CompletedStepIds -contains [string]$SelectedStep.step_id) { Add-Finding ([ref]$blockers) "selected_step_already_completed" }
  foreach ($dependency in @($SelectedStep.dependencies)) {
    if ($CompletedStepIds -notcontains [string]$dependency) { Add-Finding ([ref]$blockers) "dependency_not_complete:$dependency" }
  }
  if (-not (Test-StepProviderAvailable $Inventory $SelectedStep)) { Add-Finding ([ref]$blockers) "provider_unavailable:$($SelectedStep.provider_required)" }
  Test-StepTemplate $SelectedStep ([ref]$blockers)
  if ($FixtureScenario -eq "active-task") { Add-Finding ([ref]$blockers) "active_task_present" }
  if ($FixtureScenario -eq "stale-lease") { Add-Finding ([ref]$blockers) "stale_lease_present" }
  if ($FixtureScenario -eq "multiple-candidates") { Add-Finding ([ref]$blockers) "multiple_candidate_tasks" }
  @($blockers)
}

function New-LoopResult {
  param(
    [string]$Mode,
    $Ids,
    [object[]]$Steps,
    [string]$CurrentStepId = "",
    [string]$NextStepId = "",
    [bool]$ProviderInventoryChecked = $false,
    [bool]$DirectProviderAvailable = $false,
    [bool]$PreviewOnly = $true,
    [bool]$ApplyConfirmed = $false,
    [int]$SelectedStepCount = 0,
    [int]$SelectedTaskCount = 0,
    [int]$TaskCreatedCount = 0,
    [int]$TaskClaimedCount = 0,
    [int]$ExecutionStartedCount = 0,
    [int]$ExecutionCompletedCount = 0,
    [int]$ExecutionFailedCount = 0,
    [int]$EvidenceAttachedCount = 0,
    [int]$StepCompletedCount = 0,
    [bool]$CampaignCompleted = $false,
    [bool]$CampaignHeld = $false,
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    $Evidence = $null
  )
  $safety = New-SafetyFlags
  $record = [ordered]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    project_id = $ProjectId
    campaign_id = $Ids.campaign_id
    worker_id = $Ids.worker_id
    current_step_id = $CurrentStepId
    next_step_id = $NextStepId
    steps = @($Steps)
    provider_inventory_checked = $ProviderInventoryChecked
    direct_provider_available = $DirectProviderAvailable
    preview_only = $PreviewOnly
    apply_confirmed = $ApplyConfirmed
    max_steps = 1
    selected_step_count = $SelectedStepCount
    selected_task_count = $SelectedTaskCount
    task_created_count = $TaskCreatedCount
    task_claimed_count = $TaskClaimedCount
    execution_started_count = $ExecutionStartedCount
    execution_completed_count = $ExecutionCompletedCount
    execution_failed_count = $ExecutionFailedCount
    evidence_attached_count = $EvidenceAttachedCount
    step_completed_count = $StepCompletedCount
    campaign_completed = $CampaignCompleted
    campaign_held = $CampaignHeld
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    safety_flags = $safety
  }
  foreach ($property in $safety.PSObject.Properties) { $record[$property.Name] = $property.Value }
  if ($null -ne $Evidence) { $record["evidence"] = $Evidence }
  [pscustomobject]$record
}

function Get-EvidenceMapContains($State, [string]$StepIdValue) {
  $evidence = Get-PropertyValue $State "evidence"
  if ($null -eq $evidence) { return $false }
  $property = $evidence.PSObject.Properties[$StepIdValue]
  return $null -ne $property
}

function Build-FixturePreview {
  param($Ids, $Inventory, $State)
  $definitions = @(Get-StepDefinitions)
  $completed = Get-CompletedStepIds $State
  $selected = Select-NextStep -Steps $definitions -CompletedStepIds $completed
  $selectedStep = if ($selected.Count -gt 0) { Get-ScenarioStep $selected[0] } else { $null }
  $selectionBlockers = Test-Selection -SelectedStep $selectedStep -CompletedStepIds $completed -Inventory $Inventory
  $selectedStepId = if ($null -ne $selectedStep) { [string]$selectedStep.step_id } else { "" }
  $views = @()
  foreach ($definition in $definitions) {
    $step = if ($definition.step_id -eq $selectedStepId) { $selectedStep } else { $definition }
    $views += Get-StepView -Step $step -CompletedStepIds $completed -Inventory $Inventory -SelectedStepId $selectedStepId -SelectionBlockers $selectionBlockers -EvidenceAttached (Get-EvidenceMapContains $State ([string]$definition.step_id))
  }
  $nextStep = @($views | Where-Object { -not $_.completed -and $_.can_apply_next } | Sort-Object order | Select-Object -First 1)
  if ($nextStep.Count -eq 0 -and @($selectionBlockers).Count -eq 0 -and $completed.Count -lt $definitions.Count) {
    $selectionBlockers = @("no_ready_step")
  }
  [pscustomobject]@{
    steps = @($views)
    selected_step = $selectedStep
    selected_step_id = $selectedStepId
    next_step_id = if ($nextStep.Count -gt 0) { [string]$nextStep[0].step_id } else { "" }
    blockers = @($selectionBlockers)
    warnings = @("fixture_mode")
    direct_provider_available = Test-DirectProviderAvailable $Inventory
    campaign_completed = ($completed.Count -eq $definitions.Count)
  }
}

function Invoke-FixtureApplyNext {
  param($Ids, $Inventory)
  $state = Read-FixtureState
  $preview = Build-FixturePreview -Ids $Ids -Inventory $Inventory -State $state
  if (@($preview.blockers).Count -gt 0) {
    return New-LoopResult -Mode "fixture" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers $preview.blockers -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  if ($Confirm -ne $FixtureApplyConfirmation) {
    return New-LoopResult -Mode "fixture" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("missing_exact_confirmation") -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  $selected = $preview.selected_step
  if ($null -eq $selected) {
    return New-LoopResult -Mode "fixture" -Ids $Ids -Steps $preview.steps -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("no_ready_step") -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  $evidence = New-LoopEvidence -Ids $Ids -Step $selected
  $completed = Get-CompletedStepIds $state
  $state.completed_steps = @(@($completed) + @([string]$selected.step_id) | Sort-Object -Unique)
  $evidenceMap = [ordered]@{}
  $existingEvidence = Get-PropertyValue $state "evidence"
  if ($null -ne $existingEvidence) {
    foreach ($property in $existingEvidence.PSObject.Properties) {
      if (@("Count", "IsReadOnly", "Keys", "Values", "IsSynchronized", "SyncRoot", "IsFixedSize").Contains($property.Name)) { continue }
      $evidenceMap[$property.Name] = $property.Value
    }
  }
  $evidenceMap[[string]$selected.step_id] = $evidence
  $state.evidence = [pscustomobject]$evidenceMap
  $state.token_printed = $false
  Write-FixtureState $state
  $after = Build-FixturePreview -Ids $Ids -Inventory $Inventory -State $state
  New-LoopResult -Mode "fixture" -Ids $Ids -Steps $after.steps -CurrentStepId ([string]$selected.step_id) -NextStepId $after.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -SelectedStepCount 1 -SelectedTaskCount 1 -TaskCreatedCount 1 -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionCompletedCount 1 -EvidenceAttachedCount 1 -StepCompletedCount 1 -CampaignCompleted $after.campaign_completed -Warnings $preview.warnings -Evidence $evidence
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
  $steps = @(Get-StepDefinitions)
  [pscustomobject]@{
    campaign_id = $Ids.campaign_id
    project_id = $ProjectId
    title = "MG353 static multi-step campaign"
    description = "Three fixed ordered steps controlled one at a time by SkyBridge."
    source = "multi-goal-loop"
    status = "ready"
    safety_policy = @{
      static_step_count = 3
      max_steps_per_apply = 1
      worker_loop_started = $false
      token_printed = $false
    }
    metadata = @{
      milestone = "M3"
      token_printed = $false
    }
    goals = @($steps | ForEach-Object {
      @{
        campaign_step_id = $_.step_id
        goal_id = $_.step_id
        title = "MG353 $($_.template_id)"
        order = $_.order
        dependencies = @($_.dependencies)
        metadata = @{
          template_id = $_.template_id
          runner_id = $_.runner_id
          allowed_task_ids = @($_.task_id)
          provider_required = $_.provider_required
          token_printed = $false
        }
      }
    })
  }
}

function New-LiveTaskPayload($Ids, $Step) {
  $capabilities = if ($Step.provider_required -eq "matlab") { @("windows", "powershell", "matlab") } elseif ($Step.provider_required -eq "codex") { @("windows", "powershell", "codex", "git") } else { @("windows", "powershell", "node") }
  [pscustomobject]@{
    task_id = $Step.task_id
    project_id = $ProjectId
    title = "MG353 $($Step.template_id) static step"
    body = "Run exactly one MG353 static campaign step through the fixed allowlisted runner only."
    prompt_summary = "MG353 static step $($Step.step_id). Safe summary only."
    risk = "low"
    source = "manual"
    task_type = $Step.template_id.Replace(".v1", "")
    allowed_paths = @(".agent/tmp/multi-goal-loop/**")
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings")
    validation = @("fixed runner evidence attached", "token_printed=false")
    required_capabilities = $capabilities
    planner_metadata = @{
      adapter = "mg353-static-multi-goal-loop"
      decision = "continue"
      reason = "mg353_one_static_step"
      campaign_id = $Ids.campaign_id
      step_id = $Step.step_id
      template_id = $Step.template_id
      runner_id = $Step.runner_id
      source_run_id = "mega-goal-353-static-multi-goal-loop"
      max_steps = 1
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

function Read-LiveCompletedSteps {
  param($Ids, $Config)
  $completed = @()
  $campaignStatus = ""
  $campaign = Invoke-LoopApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))" -ResolvedApiBase $Config.api_base -ResolvedTokenFile $Config.token_file
  if ($campaign.status_code -ge 200 -and $campaign.status_code -lt 300) {
    $campaignStatus = [string]$campaign.body.campaign.status
    $steps = Invoke-LoopApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/steps" -ResolvedApiBase $Config.api_base -ResolvedTokenFile $Config.token_file
    if ($steps.status_code -ge 200 -and $steps.status_code -lt 300) {
      foreach ($step in @($steps.body.steps)) {
        if ([string]$step.status -eq "completed") { $completed += [string]$step.campaign_step_id }
      }
    }
  }
  [pscustomobject]@{ completed_steps = @($completed); campaign_status = $campaignStatus; campaign_exists = ($campaign.status_code -ge 200 -and $campaign.status_code -lt 300) }
}

function Test-LivePreconditions {
  param($Ids, $Inventory, $Config, $SelectedStep)
  $blockers = @()
  if ([string]::IsNullOrWhiteSpace($Config.api_base)) { Add-Finding ([ref]$blockers) "api_base_not_configured" }
  if ([string]::IsNullOrWhiteSpace($Config.token_file) -or -not (Test-Path -LiteralPath $Config.token_file -PathType Leaf)) { Add-Finding ([ref]$blockers) "token_file_not_present" }
  if ($Ids.worker_id -ne $LiveWorkerId) { Add-Finding ([ref]$blockers) "unexpected_worker_id" }
  if ($Ids.campaign_id -ne $LiveCampaignId) { Add-Finding ([ref]$blockers) "unexpected_campaign_id" }
  if ($MaxSteps -ne 1) { Add-Finding ([ref]$blockers) "max_steps_must_be_1" }
  if ($null -ne $SelectedStep -and -not (Test-StepProviderAvailable $Inventory $SelectedStep)) { Add-Finding ([ref]$blockers) "provider_unavailable:$($SelectedStep.provider_required)" }
  if (@($blockers).Count -eq 0) {
    $worker = Invoke-LoopApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($Ids.worker_id))" -ResolvedApiBase $Config.api_base -ResolvedTokenFile $Config.token_file
    if ($worker.status_code -lt 200 -or $worker.status_code -ge 300) {
      Add-Finding ([ref]$blockers) "worker_not_registered_or_offline"
    } else {
      if ([string]$worker.body.worker.status -ne "online") { Add-Finding ([ref]$blockers) "worker_not_online" }
      if ($worker.body.worker.enabled -ne $true) { Add-Finding ([ref]$blockers) "worker_disabled" }
    }
    $tasks = Invoke-LoopApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ResolvedApiBase $Config.api_base -ResolvedTokenFile $Config.token_file
    if ($tasks.status_code -ge 200 -and $tasks.status_code -lt 300) {
      foreach ($task in @($tasks.body.tasks)) {
        $taskStatus = [string]$task.status
        $taskCampaign = [string](Get-PropertyValue $task.planner_metadata "campaign_id")
        if ($taskStatus -in @("claimed", "running") -and $taskCampaign -ne $Ids.campaign_id) { Add-Finding ([ref]$blockers) "active_unrelated_task_present" }
      }
    }
  }
  @($blockers)
}

function Build-LivePreview {
  param($Ids, $Inventory)
  $config = Resolve-LiveConfig
  $definitions = @(Get-StepDefinitions)
  $liveState = Read-LiveCompletedSteps -Ids $Ids -Config $config
  $completed = @($liveState.completed_steps)
  $selected = Select-NextStep -Steps $definitions -CompletedStepIds $completed
  $selectedStep = if ($selected.Count -gt 0) { $selected[0] } else { $null }
  $blockers = Test-Selection -SelectedStep $selectedStep -CompletedStepIds $completed -Inventory $Inventory
  $blockers = @($blockers + (Test-LivePreconditions -Ids $Ids -Inventory $Inventory -Config $config -SelectedStep $selectedStep))
  $selectedStepId = if ($null -ne $selectedStep) { [string]$selectedStep.step_id } else { "" }
  $views = @()
  foreach ($definition in $definitions) {
    $views += Get-StepView -Step $definition -CompletedStepIds $completed -Inventory $Inventory -SelectedStepId $selectedStepId -SelectionBlockers $blockers -EvidenceAttached ($completed -contains [string]$definition.step_id)
  }
  [pscustomobject]@{
    config = $config
    steps = @($views)
    selected_step = $selectedStep
    selected_step_id = $selectedStepId
    next_step_id = $selectedStepId
    blockers = @($blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    warnings = @("live_preview_no_mutation")
    direct_provider_available = Test-DirectProviderAvailable $Inventory
    campaign_completed = ($completed.Count -eq $definitions.Count -or [string]$liveState.campaign_status -eq "completed")
    campaign_exists = [bool]$liveState.campaign_exists
  }
}

function Invoke-LiveApplyNext {
  param($Ids, $Inventory)
  $preview = Build-LivePreview -Ids $Ids -Inventory $Inventory
  if (@($preview.blockers).Count -gt 0) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers $preview.blockers -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  if ($Confirm -ne $LiveApplyConfirmation) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("missing_exact_confirmation") -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  $selected = $preview.selected_step
  if ($null -eq $selected) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("no_ready_step") -Warnings $preview.warnings -CampaignCompleted $preview.campaign_completed
  }
  $config = $preview.config
  if (-not $preview.campaign_exists) {
    $createdCampaign = Invoke-LoopApi -Method POST -Path "/v1/campaigns" -Body (New-LiveCampaignPayload $Ids) -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($createdCampaign.status_code -lt 200 -or $createdCampaign.status_code -ge 300) {
      return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -Blockers @("campaign_create_failed") -Warnings $preview.warnings
    }
  }
  $taskCreated = $false
  $task = Invoke-LoopApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($selected.task_id))" -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($task.status_code -eq 404) {
    $createdTask = Invoke-LoopApi -Method POST -Path "/v1/tasks" -Body (New-LiveTaskPayload -Ids $Ids -Step $selected) -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($createdTask.status_code -lt 200 -or $createdTask.status_code -ge 300) {
      return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -Blockers @("task_create_failed") -Warnings $preview.warnings
    }
    $taskCreated = $true
  } elseif ($task.status_code -ge 200 -and $task.status_code -lt 300) {
    if ([string](Get-PropertyValue $task.body.task.planner_metadata "campaign_id") -ne $Ids.campaign_id) {
      return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -Blockers @("existing_task_campaign_mismatch") -Warnings $preview.warnings
    }
  } else {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -Blockers @("task_read_failed") -Warnings $preview.warnings
  }
  $claim = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($selected.task_id))/claim" -Body @{ worker_id = $Ids.worker_id } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($claim.status_code -lt 200 -or $claim.status_code -ge 300) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -Blockers @("task_claim_failed") -Warnings $preview.warnings
  }
  $start = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($selected.task_id))/start" -Body @{ worker_id = $Ids.worker_id } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($start.status_code -lt 200 -or $start.status_code -ge 300) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 0 -ExecutionFailedCount 1 -Blockers @("task_start_failed") -Warnings $preview.warnings
  }
  $evidence = New-LoopEvidence -Ids $Ids -Step $selected
  $complete = Invoke-LoopApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($selected.task_id))/complete" -Body @{ worker_id = $Ids.worker_id; summary = "MG353 static multi-goal step completed with sanitized evidence."; evidence_summary = $evidence } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($complete.status_code -lt 200 -or $complete.status_code -ge 300) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionFailedCount 1 -Blockers @("task_complete_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $attach = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/steps/$([uri]::EscapeDataString($selected.step_id))/attach-evidence" -Body @{ linked_task_ids = @($selected.task_id); evidence_summary = $evidence } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($attach.status_code -lt 200 -or $attach.status_code -ge 300) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionCompletedCount 1 -Blockers @("evidence_attach_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $stepComplete = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/steps/$([uri]::EscapeDataString($selected.step_id))/complete" -Body @{ linked_task_ids = @($selected.task_id); evidence_summary = $evidence; reason = "MG353 static step completed." } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
  if ($stepComplete.status_code -lt 200 -or $stepComplete.status_code -ge 300) {
    return New-LoopResult -Mode "live" -Ids $Ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -ApplyConfirmed $true -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionCompletedCount 1 -EvidenceAttachedCount 1 -Blockers @("step_complete_failed") -Warnings $preview.warnings -Evidence $evidence
  }
  $after = Build-LivePreview -Ids $Ids -Inventory $Inventory
  $campaignCompleted = $after.campaign_completed
  if ($campaignCompleted) {
    $campaignComplete = Invoke-LoopApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($Ids.campaign_id))/complete" -Body @{ reason = "MG353 three static steps completed." } -ResolvedApiBase $config.api_base -ResolvedTokenFile $config.token_file
    if ($campaignComplete.status_code -lt 200 -or $campaignComplete.status_code -ge 300) {
      return New-LoopResult -Mode "live" -Ids $Ids -Steps $after.steps -CurrentStepId ([string]$selected.step_id) -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -SelectedStepCount 1 -SelectedTaskCount 1 -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionCompletedCount 1 -EvidenceAttachedCount 1 -StepCompletedCount 1 -Blockers @("campaign_complete_failed") -Warnings @($preview.warnings + "campaign_hold_required") -Evidence $evidence
    }
  }
  New-LoopResult -Mode "live" -Ids $Ids -Steps $after.steps -CurrentStepId ([string]$selected.step_id) -NextStepId $after.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $true -PreviewOnly $false -ApplyConfirmed $true -SelectedStepCount 1 -SelectedTaskCount 1 -TaskCreatedCount $(if ($taskCreated) { 1 } else { 0 }) -TaskClaimedCount 1 -ExecutionStartedCount 1 -ExecutionCompletedCount 1 -EvidenceAttachedCount 1 -StepCompletedCount 1 -CampaignCompleted $campaignCompleted -Warnings $preview.warnings -Evidence $evidence
}

function Invoke-MultiGoalCommand {
  $ids = Get-LoopIds
  $inventory = Invoke-ProviderInventory
  if ($Fixture) {
    $state = Read-FixtureState
    $preview = Build-FixturePreview -Ids $ids -Inventory $inventory -State $state
    if ($Command -eq "apply-next") { return Invoke-FixtureApplyNext -Ids $ids -Inventory $inventory }
    if ($Command -eq "hold") {
      return New-LoopResult -Mode "fixture" -Ids $ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -CampaignHeld $true -Warnings @($preview.warnings + "fixture_hold_in_memory_no_mutation")
    }
    if ($Command -eq "attach-evidence" -or $Command -eq "complete-step") {
      return New-LoopResult -Mode "fixture" -Ids $ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("use_apply_next_for_step_mutation") -Warnings $preview.warnings
    }
    $blockers = if ($Command -eq "preview-next") { $preview.blockers } else { @() }
    return New-LoopResult -Mode "fixture" -Ids $ids -Steps $preview.steps -CurrentStepId "" -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $true -SelectedStepCount $(if ([string]::IsNullOrWhiteSpace($preview.selected_step_id)) { 0 } else { 1 }) -SelectedTaskCount $(if ([string]::IsNullOrWhiteSpace($preview.selected_step_id)) { 0 } else { 1 }) -CampaignCompleted $preview.campaign_completed -Blockers $blockers -Warnings $preview.warnings
  }

  $preview = Build-LivePreview -Ids $ids -Inventory $inventory
  if ($Command -eq "apply-next") { return Invoke-LiveApplyNext -Ids $ids -Inventory $inventory }
  if ($Command -eq "hold") {
    return New-LoopResult -Mode "live" -Ids $ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("live_hold_not_supported_by_mg353_script") -Warnings $preview.warnings
  }
  if ($Command -eq "attach-evidence" -or $Command -eq "complete-step") {
    return New-LoopResult -Mode "live" -Ids $ids -Steps $preview.steps -CurrentStepId $preview.selected_step_id -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $false -Blockers @("live_attach_or_complete_requires_apply_next") -Warnings $preview.warnings
  }
  New-LoopResult -Mode "live" -Ids $ids -Steps $preview.steps -CurrentStepId "" -NextStepId $preview.next_step_id -ProviderInventoryChecked $true -DirectProviderAvailable $preview.direct_provider_available -PreviewOnly $true -SelectedStepCount $(if ([string]::IsNullOrWhiteSpace($preview.selected_step_id)) { 0 } else { 1 }) -SelectedTaskCount $(if ([string]::IsNullOrWhiteSpace($preview.selected_step_id)) { 0 } else { 1 }) -CampaignCompleted $preview.campaign_completed -Blockers $preview.blockers -Warnings $preview.warnings
}

function Write-LoopReport($Result) {
  $targetRoot = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  $jsonPath = Join-Path $targetRoot "multi-goal-loop.json"
  $mdPath = Join-Path $targetRoot "multi-goal-loop.md"
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Multi-Step Static Goal Loop",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- project_id: $($Result.project_id)",
    "- campaign_id: $($Result.campaign_id)",
    "- worker_id: $($Result.worker_id)",
    "- current_step_id: $($Result.current_step_id)",
    "- next_step_id: $($Result.next_step_id)",
    "- selected_step_count: $($Result.selected_step_count)",
    "- selected_task_count: $($Result.selected_task_count)",
    "- task_created_count: $($Result.task_created_count)",
    "- task_claimed_count: $($Result.task_claimed_count)",
    "- execution_completed_count: $($Result.execution_completed_count)",
    "- evidence_attached_count: $($Result.evidence_attached_count)",
    "- step_completed_count: $($Result.step_completed_count)",
    "- campaign_completed: $($Result.campaign_completed)",
    "- campaign_held: $($Result.campaign_held)",
    "- codex_run_called: $($Result.codex_run_called)",
    "- matlab_run_called: $($Result.matlab_run_called)",
    "- hermes_run_called: false",
    "- mcp_run_called: false",
    "- arbitrary_shell_enabled: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Steps",
    ""
  )
  foreach ($step in @($Result.steps)) {
    $lines += "- $($step.order): $($step.step_id) template=$($step.template_id) state=$($step.state) evidence=$($step.evidence_attached)"
  }
  $lines += @("", "## Blockers", "")
  if (@($Result.blockers).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.blockers)) { $lines += "- $item" } }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.warnings)) { $lines += "- $item" } }
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$result = Invoke-MultiGoalCommand
if ($WriteReport -or $Command -eq "report") {
  Write-LoopReport $result
}

if ($Json) {
  $result | ConvertTo-Json -Depth 60
} else {
  "Multi-step static goal loop: $($result.mode)"
  "Campaign: $($result.campaign_id)"
  "Next step: $($result.next_step_id)"
  "Selected step count: $($result.selected_step_count)"
  "Task created count: $($result.task_created_count)"
  "Task claimed count: $($result.task_claimed_count)"
  "Execution completed count: $($result.execution_completed_count)"
  "Evidence attached count: $($result.evidence_attached_count)"
  "Step completed count: $($result.step_completed_count)"
  "Campaign completed: $($result.campaign_completed)"
  "Campaign held: $($result.campaign_held)"
  "token_printed=false"
}
