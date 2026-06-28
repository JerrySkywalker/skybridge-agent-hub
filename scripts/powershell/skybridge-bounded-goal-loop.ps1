[CmdletBinding()]
param(
  [ValidateSet("status", "preview", "apply-one", "run-fixture-scenario", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/bounded-goal-loop",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "",
  [string]$WorkerId = "",
  [int]$GoalBudgetRemaining = 1,
  [int]$GoalBudgetLimit = 1,
  [string]$Objective = "Create one safe follow-up goal candidate for bounded loop review.",
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [string]$ReviewedCandidatePath = "",
  [int]$MaxActionsPerRun = 1,
  [int]$MaxStepsPerRun = 1,
  [int]$MaxGeneratedGoalsPerRun = 1,
  [switch]$Fixture,
  [switch]$Live,
  [switch]$UseCodex,
  [switch]$NoCodex,
  [string]$Confirm = "",
  [ValidateSet("ready-step", "reviewed-candidate", "generate", "budget-exhausted", "priority")]
  [string]$Scenario = "ready-step"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.bounded_goal_loop.v1"
$EvidenceSchema = "skybridge.bounded_goal_loop_evidence.v1"
$MetadataSchema = "skybridge.generated_goal_metadata.v1"
$BoundedConfirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$CodexConfirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$AppendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"

if ($Live) {
  $Fixture = $false
  $Mode = "live"
} elseif ($Fixture -or -not $Live) {
  $Fixture = $true
  $Mode = "fixture"
} else {
  $Mode = "local"
}

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function ConvertTo-SafeJson($Value) {
  $Value | ConvertTo-Json -Depth 90
}

function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
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
  $value
}

function Resolve-OutputRoot {
  $fullTarget = Resolve-RepoPath $OutputDir
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/bounded-goal-loop"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/bounded-goal-loop."
  }
  $fullTarget
}

function Get-Sha256Text([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Test-ConfirmContains([string]$Text, [string]$Needle) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $Text -split "[;|,\s]+" | Where-Object { $_ -eq $Needle } | Select-Object -First 1 | ForEach-Object { $true }
}

function New-SafetyFlags {
  [pscustomobject]@{
    codex_generation_called = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    appended_step_executed = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    token_printed = $false
  }
}

function Invoke-ProviderInventory {
  $providerScript = Join-Path $PSScriptRoot "skybridge-tool-provider.ps1"
  if (-not (Test-Path -LiteralPath $providerScript -PathType Leaf)) {
    return [pscustomobject]@{
      checked = $false
      direct_available = $false
      warnings = @("tool_provider_script_missing")
      blockers = @("provider_inventory_unavailable")
    }
  }
  try {
    $args = @("-Command", "inventory", "-Fixture", "-NoVersionProbe", "-Json")
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $providerScript @args
    if ($LASTEXITCODE -ne 0) { throw "provider_inventory_failed" }
    $inventory = (($raw | Out-String).Trim() | ConvertFrom-Json)
    $direct = @($inventory.providers | Where-Object { $_.provider_id -eq "direct-local" -or $_.provider_type -eq "direct" } | Select-Object -First 1)
    [pscustomobject]@{
      checked = $true
      direct_available = [bool]($direct.Count -gt 0 -and $direct[0].status -eq "available")
      warnings = @()
      blockers = @()
    }
  } catch {
    [pscustomobject]@{
      checked = $false
      direct_available = $false
      warnings = @("provider_inventory_probe_failed")
      blockers = @("provider_inventory_unavailable")
    }
  }
}

function Get-ScenarioState {
  $budget = [Math]::Max(0, $GoalBudgetRemaining)
  switch ($Scenario) {
    "ready-step" {
      return [pscustomobject]@{
        campaign_id = "bounded-loop-fixture-ready-step-356"
        ready_step_detected = $true
        reviewed_candidate_detected = $false
        generated_candidate_detected = $false
        selected_step_id = "bounded-loop-safe-step-356-001"
        selected_task_id = "bounded-loop-safe-task-356-001"
        selected_candidate_path_safe = ""
        selected_candidate_hash = ""
        generated_goal_id = ""
        generated_goal_path_safe = ""
        appended_step_id = ""
        appended_step_state = ""
        budget = $budget
      }
    }
    "reviewed-candidate" {
      return [pscustomobject]@{
        campaign_id = "bounded-loop-fixture-reviewed-candidate-356"
        ready_step_detected = $false
        reviewed_candidate_detected = $true
        generated_candidate_detected = $false
        selected_step_id = ""
        selected_task_id = ""
        selected_candidate_path_safe = if ($ReviewedCandidatePath) { Convert-ToSafePath $ReviewedCandidatePath } else { ".agent/tmp/goal-append/review-state/generated-goal-355-fixture.review.json" }
        selected_candidate_hash = if ($ExpectedHash) { $ExpectedHash } else { "fixture-reviewed-candidate-hash" }
        generated_goal_id = "generated-goal-355-fixture"
        generated_goal_path_safe = ""
        appended_step_id = "bounded-loop-appended-generated-goal-356-001"
        appended_step_state = "pending"
        budget = $budget
      }
    }
    "generate" {
      return [pscustomobject]@{
        campaign_id = "bounded-loop-fixture-generate-356"
        ready_step_detected = $false
        reviewed_candidate_detected = $false
        generated_candidate_detected = $false
        selected_step_id = ""
        selected_task_id = ""
        selected_candidate_path_safe = ""
        selected_candidate_hash = ""
        generated_goal_id = "bounded-loop-generated-goal-356-fixture"
        generated_goal_path_safe = ".agent/tmp/bounded-goal-loop/generated/bounded-loop-generated-goal-356-fixture.md"
        appended_step_id = ""
        appended_step_state = ""
        budget = $budget
      }
    }
    "budget-exhausted" {
      return [pscustomobject]@{
        campaign_id = "bounded-loop-fixture-budget-exhausted-356"
        ready_step_detected = $false
        reviewed_candidate_detected = $false
        generated_candidate_detected = $false
        selected_step_id = ""
        selected_task_id = ""
        selected_candidate_path_safe = ""
        selected_candidate_hash = ""
        generated_goal_id = ""
        generated_goal_path_safe = ""
        appended_step_id = ""
        appended_step_state = ""
        budget = 0
      }
    }
    "priority" {
      return [pscustomobject]@{
        campaign_id = "bounded-loop-fixture-priority-356"
        ready_step_detected = $true
        reviewed_candidate_detected = $true
        generated_candidate_detected = $false
        selected_step_id = "bounded-loop-safe-step-356-001"
        selected_task_id = "bounded-loop-safe-task-356-001"
        selected_candidate_path_safe = ".agent/tmp/goal-append/review-state/generated-goal-355-fixture.review.json"
        selected_candidate_hash = "fixture-reviewed-candidate-hash"
        generated_goal_id = ""
        generated_goal_path_safe = ""
        appended_step_id = ""
        appended_step_state = ""
        budget = $budget
      }
    }
  }
}

function Get-SelectedAction($State, [ref]$Warnings, [ref]$Blockers) {
  if ($GoalBudgetLimit -lt 0 -or $State.budget -lt 0) {
    Add-Finding $Blockers "invalid_budget"
    return "hold"
  }
  if ($MaxActionsPerRun -ne 1) { Add-Finding $Blockers "max_actions_per_run_must_be_1" }
  if ($MaxStepsPerRun -ne 1) { Add-Finding $Blockers "max_steps_per_run_must_be_1" }
  if ($MaxGeneratedGoalsPerRun -ne 1) { Add-Finding $Blockers "max_generated_goals_per_run_must_be_1" }
  if ($Blockers.Value.Count -gt 0) { return "hold" }
  if ($State.ready_step_detected) { return "execute_ready_step" }
  if ($State.reviewed_candidate_detected -and $State.budget -gt 0) { return "append_reviewed_goal" }
  if ($State.reviewed_candidate_detected -and $State.budget -le 0) {
    Add-Finding $Warnings "reviewed_candidate_blocked_by_budget"
    return "hold"
  }
  if ($State.budget -gt 0) { return "generate_proposed_goal" }
  "hold"
}

function New-GeneratedGoalMarkdown([string]$GoalId, [int]$BudgetRemaining) {
  $metadata = [ordered]@{
    schema = $MetadataSchema
    goal_id = $GoalId
    title = "Bounded Loop Generated Goal 356 Fixture"
    order = 1
    risk = "low"
    task_type = "docs-validation"
    allowed_task_types = @("docs-validation", "local-smoke")
    blocked_task_types = @("task-execution", "worker-loop", "production-deploy", "release-mutation")
    requires = @("human review", "MG355 append review gate")
    expected_outputs = @("one reviewed documentation validation goal")
    advance_gate = [ordered]@{
      human_review_required = $true
      import_allowed = $false
      execution_allowed = $false
    }
    generated_by = "skybridge-bounded-goal-loop-fixture"
    generation_provider = "fixture"
    source_campaign_id = "bounded-loop-fixture-generate-356"
    source_project_id = $ProjectId
    goal_budget_remaining = $BudgetRemaining
    human_review_required = $true
    import_allowed = $false
    execution_allowed = $false
    token_printed = $false
  }
  $json = $metadata | ConvertTo-Json -Depth 20
  $fence = '```'
  @(
    "$fence" + "json",
    $json,
    $fence,
    "",
    "# Bounded Loop Generated Goal 356 Fixture",
    "",
    "## Context",
    "This candidate is deterministic fixture output from MG356.",
    "",
    "## Mission",
    "Validate a future documentation-only goal through human review before any import or execution.",
    "",
    "## Hard Safety Boundaries",
    "- No task creation, task claim, execution, worker loop, queue runner, release mutation, or production infrastructure change.",
    "- No raw prompts, raw logs, stdout, stderr, credentials, cookies, provider auth headers, proxy profiles, or complete environment listings.",
    "- token_printed=false",
    "",
    "## Allowed Scope",
    "- Documentation validation and sanitized reporting only.",
    "",
    "## Forbidden Scope",
    "- No self-approval, self-import, self-append, or self-execution.",
    "",
    "## Implementation Requirements",
    "- Add one reviewable documentation validation step in a future goal only after explicit review.",
    "",
    "## Validation Requirements",
    "- Run fixture-safe smokes and keep generated content unexecuted.",
    "",
    "## CI/CD Requirements",
    "- CI must not require live cloud, Codex, MATLAB, Hermes, or MCP.",
    "",
    "## Manual Milestone Script Requirement",
    "- Provide a manual review checkpoint before import.",
    "",
    "## Evidence Requirements",
    "- Report hash, review state, and safety flags only.",
    "",
    "## Final Report Requirements",
    "- Include token_printed=false and no-execution status."
  ) -join [Environment]::NewLine
}

function Write-Reports($Result) {
  if (-not $WriteReport) { return $Result }
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "bounded-goal-loop.json"
  $mdPath = Join-Path $root "bounded-goal-loop.md"
  ConvertTo-SafeJson $Result | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  @(
    "# Bounded Goal Budget Loop",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- campaign_id: $($Result.campaign_id)",
    "- selected_action: $($Result.selected_action)",
    "- selected_action_reason: $($Result.selected_action_reason)",
    "- goal_budget_remaining_before: $($Result.goal_budget_remaining_before)",
    "- goal_budget_remaining_after: $($Result.goal_budget_remaining_after)",
    "- action_performed: $($Result.action_performed)",
    "- task_created/task_claimed/execution_started: $($Result.task_created)/$($Result.task_claimed)/$($Result.execution_started)",
    "- generated_goal_path_safe: $($Result.generated_goal_path_safe)",
    "- appended_step_id/state: $($Result.appended_step_id)/$($Result.appended_step_state)",
    "- worker_loop_started: false",
    "- token_printed: false"
  ) -join [Environment]::NewLine | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Result
}

$warnings = @()
$blockers = @()
$provider = Invoke-ProviderInventory
foreach ($warning in @($provider.warnings)) { Add-Finding ([ref]$warnings) $warning }
foreach ($blocker in @($provider.blockers)) { Add-Finding ([ref]$blockers) $blocker }

if ($Mode -eq "live") {
  Add-Finding ([ref]$warnings) "live_preview_only_in_mg356"
  if ($Command -eq "apply-one") { Add-Finding ([ref]$blockers) "live_apply_deferred_to_future_goal" }
}

$state = Get-ScenarioState
if (-not [string]::IsNullOrWhiteSpace($CampaignId)) {
  $state.campaign_id = $CampaignId
}
if ($Command -eq "status" -or $Command -eq "safe-summary" -or $Command -eq "report") {
  $CommandEffective = "preview"
} elseif ($Command -eq "run-fixture-scenario") {
  $CommandEffective = if (Test-ConfirmContains $Confirm $BoundedConfirm) { "apply-one" } else { "preview" }
} else {
  $CommandEffective = $Command
}

$selectedAction = Get-SelectedAction $state ([ref]$warnings) ([ref]$blockers)
$previewOnly = ($CommandEffective -ne "apply-one")
$applyConfirmed = Test-ConfirmContains $Confirm $BoundedConfirm
if ($CommandEffective -eq "apply-one" -and -not $applyConfirmed) {
  Add-Finding ([ref]$blockers) "missing_bounded_loop_confirmation"
}
if ($CommandEffective -eq "apply-one" -and $selectedAction -eq "append_reviewed_goal" -and -not (Test-ConfirmContains $Confirm $AppendConfirm)) {
  Add-Finding ([ref]$warnings) "append_confirmation_scoped_by_bounded_loop_fixture"
}
if ($CommandEffective -eq "apply-one" -and $selectedAction -eq "generate_proposed_goal" -and $UseCodex -and -not (Test-ConfirmContains $Confirm $CodexConfirm)) {
  Add-Finding ([ref]$blockers) "missing_codex_generation_confirmation"
}

$canApply = ($CommandEffective -eq "apply-one" -and $applyConfirmed -and $blockers.Count -eq 0)
$taskCreated = $false
$taskClaimed = $false
$executionStarted = $false
$executionCompleted = $false
$evidenceAttached = $false
$stepCompleted = $false
$goalGenerated = $false
$goalReviewed = $false
$goalAppended = $false
$campaignCompleted = $false
$campaignHeld = $false
$actionPerformed = $false
$generatedHash = ""
$goalBudgetAfter = $state.budget
$safety = New-SafetyFlags

if ($canApply) {
  switch ($selectedAction) {
    "execute_ready_step" {
      $taskCreated = $true
      $taskClaimed = $true
      $executionStarted = $true
      $executionCompleted = $true
      $evidenceAttached = $true
      $stepCompleted = $true
      $actionPerformed = $true
    }
    "append_reviewed_goal" {
      $goalReviewed = $true
      $goalAppended = $true
      $actionPerformed = $true
      $goalBudgetAfter = [Math]::Max(0, $state.budget - 1)
    }
    "generate_proposed_goal" {
      $goalGenerated = $true
      $actionPerformed = $true
      $goalBudgetAfter = $state.budget
      $outputRoot = Resolve-OutputRoot
      $generatedRoot = Join-Path $outputRoot "generated"
      New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null
      $generatedPath = Join-Path $generatedRoot "bounded-loop-generated-goal-356-fixture.md"
      $content = New-GeneratedGoalMarkdown $state.generated_goal_id $state.budget
      Set-Content -LiteralPath $generatedPath -Value $content -Encoding UTF8
      $generatedHash = Get-Sha256Text $content
      $state.generated_goal_path_safe = Convert-ToSafePath $generatedPath
      $state.selected_candidate_hash = $generatedHash
    }
    "hold" {
      $campaignHeld = $true
    }
  }
} elseif ($selectedAction -eq "hold") {
  $campaignHeld = $true
}

$actionCount = if ($actionPerformed) { 1 } else { 0 }
$reason = switch ($selectedAction) {
  "execute_ready_step" { "ready_step_has_priority" }
  "append_reviewed_goal" { "no_ready_step_reviewed_candidate_available" }
  "generate_proposed_goal" { "no_ready_step_no_reviewed_candidate_budget_remaining" }
  "hold" { if ($state.budget -le 0) { "budget_exhausted_no_ready_step" } else { "blocked_or_preview_only" } }
  default { "no_action_selected" }
}

$evidence = [pscustomobject]@{
  schema = $EvidenceSchema
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  campaign_id = $state.campaign_id
  selected_action = $selectedAction
  selected_action_reason = $reason
  goal_budget_remaining_before = $state.budget
  goal_budget_remaining_after = $goalBudgetAfter
  selected_step_id = $state.selected_step_id
  selected_task_id = $state.selected_task_id
  generated_goal_id = if ($goalGenerated) { $state.generated_goal_id } else { "" }
  generated_goal_hash = $generatedHash
  appended_step_id = if ($goalAppended) { $state.appended_step_id } else { "" }
  task_created = $taskCreated
  task_claimed = $taskClaimed
  execution_started = $executionStarted
  execution_completed = $executionCompleted
  goal_generated = $goalGenerated
  goal_appended = $goalAppended
  appended_step_executed = $false
  codex_generation_called = $false
  codex_run_called = $false
  matlab_run_called = $false
  hermes_run_called = $false
  mcp_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
}

$result = [pscustomobject]@{
  schema = $Schema
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  mode = $Mode
  project_id = $ProjectId
  campaign_id = $state.campaign_id
  worker_id = if ($WorkerId) { $WorkerId } else { "fixture-worker-356" }
  goal_budget_limit = $GoalBudgetLimit
  goal_budget_remaining_before = $state.budget
  goal_budget_remaining_after = $goalBudgetAfter
  max_actions_per_run = $MaxActionsPerRun
  max_steps_per_run = $MaxStepsPerRun
  max_generated_goals_per_run = $MaxGeneratedGoalsPerRun
  selected_action = $selectedAction
  selected_action_reason = $reason
  preview_only = $previewOnly
  apply_confirmed = $applyConfirmed
  provider_inventory_checked = $provider.checked
  direct_provider_available = $provider.direct_available
  ready_step_detected = $state.ready_step_detected
  reviewed_candidate_detected = $state.reviewed_candidate_detected
  generated_candidate_detected = $state.generated_candidate_detected
  selected_step_id = $state.selected_step_id
  selected_task_id = $state.selected_task_id
  selected_candidate_path_safe = $state.selected_candidate_path_safe
  selected_candidate_hash = if ($generatedHash) { $generatedHash } else { $state.selected_candidate_hash }
  generated_goal_id = if ($selectedAction -eq "generate_proposed_goal") { $state.generated_goal_id } else { "" }
  generated_goal_path_safe = if ($selectedAction -eq "generate_proposed_goal") { $state.generated_goal_path_safe } else { "" }
  appended_step_id = if ($selectedAction -eq "append_reviewed_goal") { $state.appended_step_id } else { "" }
  appended_step_state = if ($selectedAction -eq "append_reviewed_goal") { $state.appended_step_state } else { "" }
  action_performed = $actionPerformed
  action_count = $actionCount
  task_created = $taskCreated
  task_claimed = $taskClaimed
  execution_started = $executionStarted
  execution_completed = $executionCompleted
  evidence_attached = $evidenceAttached
  step_completed = $stepCompleted
  goal_generated = $goalGenerated
  goal_reviewed = $goalReviewed
  goal_appended = $goalAppended
  campaign_completed = $campaignCompleted
  campaign_held = $campaignHeld
  task_created_count = if ($taskCreated) { 1 } else { 0 }
  task_claimed_count = if ($taskClaimed) { 1 } else { 0 }
  execution_started_count = if ($executionStarted) { 1 } else { 0 }
  execution_completed_count = if ($executionCompleted) { 1 } else { 0 }
  goal_generated_count = if ($goalGenerated) { 1 } else { 0 }
  goal_appended_count = if ($goalAppended) { 1 } else { 0 }
  appended_step_executed = $false
  codex_generation_called = $false
  codex_run_called = $false
  matlab_run_called = $false
  hermes_run_called = $false
  mcp_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  blockers = @($blockers)
  warnings = @($warnings)
  safety_flags = $safety
  evidence = $evidence
  token_printed = $false
}

$result = Write-Reports $result

if ($Json) {
  $result | ConvertTo-Json -Depth 90
} elseif ($Command -eq "safe-summary") {
  Write-Host "bounded_goal_loop selected_action=$($result.selected_action) action_count=$($result.action_count) worker_loop_started=false token_printed=false"
} else {
  $result | Format-List
}
