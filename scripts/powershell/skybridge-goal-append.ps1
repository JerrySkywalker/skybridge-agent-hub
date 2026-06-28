[CmdletBinding()]
param(
  [ValidateSet("status", "review-preview", "approve", "reject", "append-preview", "append-apply", "validate-candidate", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$CandidatePath = "",
  [string]$GoalId = "",
  [string]$CampaignId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [int]$GoalBudgetRemaining = 1,
  [string]$ReviewStateDir = "",
  [string]$ReviewedGoalDir = "",
  [string]$OutputDir = ".agent/tmp/goal-append",
  [string]$ApprovalReason = "",
  [string]$RejectReason = "",
  [string]$AppendReason = "",
  [string]$ExpectedHash = "",
  [switch]$Fixture,
  [switch]$Live,
  [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.goal_append_review.v1"
$EvidenceSchema = "skybridge.goal_append_evidence.v1"
$MetadataSchema = "skybridge.generated_goal_metadata.v1"
$ApproveConfirmation = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$AppendConfirmation = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
$FixtureCampaignId = "goal-append-fixture-campaign-355"
$FixtureGoalId = "generated-goal-355-fixture"
$FixtureTitle = "Generated Goal 355 Fixture"
$FixtureStepId = "appended-generated-goal-355-fixture-step"
$LiveCampaignId = "live-goal-append-campaign-355-001"
$LiveStepId = "live-appended-generated-goal-step-355-001"

$hasCandidatePath = -not [string]::IsNullOrWhiteSpace($CandidatePath)
if ($Live) {
  $Fixture = $false
  $Mode = "live"
} elseif ($Fixture -or -not $hasCandidatePath) {
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

function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Resolve-OutputRoot {
  $targetRoot = Resolve-RepoPath $OutputDir
  $fullTarget = [IO.Path]::GetFullPath($targetRoot)
  $agentGoalAppend = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/goal-append"))
  if (-not $fullTarget.StartsWith($agentGoalAppend, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/goal-append."
  }
  $fullTarget
}

function Resolve-ReviewStateRoot {
  if ([string]::IsNullOrWhiteSpace($ReviewStateDir)) {
    return [IO.Path]::GetFullPath((Join-Path (Resolve-OutputRoot) "review-state"))
  }
  $full = Resolve-RepoPath $ReviewStateDir
  $agentTmp = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  if (-not $full.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ReviewStateDir must be under .agent/tmp."
  }
  $full
}

function Resolve-ReviewedGoalRoot {
  if ([string]::IsNullOrWhiteSpace($ReviewedGoalDir)) {
    return [IO.Path]::GetFullPath((Join-Path (Resolve-OutputRoot) "reviewed-goals"))
  }
  $full = Resolve-RepoPath $ReviewedGoalDir
  $agentTmp = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $goalsReviewed = [IO.Path]::GetFullPath((Join-Path $RepoRoot "goals/reviewed"))
  if ($full.StartsWith($goalsReviewed, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full
  }
  if (-not $full.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ReviewedGoalDir must be under .agent/tmp or goals/reviewed."
  }
  $full
}

function Test-PathTraversal([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $Path -match "(^|[\\/])\.\.([\\/]|$)"
}

function Test-AllowedCandidatePath([string]$FullPath) {
  $allowedRoots = @(
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/generated-goals")),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/goal-append")),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/reviewed-goals")),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot "goals/reviewed")),
    [IO.Path]::GetFullPath((Join-Path $RepoRoot "goals/proposed"))
  )
  foreach ($root in $allowedRoots) {
    if ($FullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  $false
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

function Sanitize-Reason([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{8,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe.Trim()
  if ($safe.Length -gt 240) { return $safe.Substring(0, 240) }
  $safe
}

function Test-SafeGoalId([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  if ($Value -match "[\\/]" -or $Value.Contains("..")) { return $false }
  $Value -match "^[a-z0-9][a-z0-9._-]{2,160}$"
}

function New-SafetyFlags {
  [pscustomobject]@{
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    token_printed = $false
  }
}

function New-FixtureCandidateMarkdown {
  $metadata = [ordered]@{
    schema = $MetadataSchema
    goal_id = $FixtureGoalId
    title = $FixtureTitle
    order = 1
    risk = "low"
    task_type = "docs-validation"
    allowed_task_types = @("docs-validation", "local-smoke")
    blocked_task_types = @("task-execution", "worker-loop", "production-deploy", "secret-rotation", "release-mutation")
    requires = @("human review", "MG355 append review gate")
    expected_outputs = @("one appended non-executed campaign step")
    advance_gate = [ordered]@{
      human_review_required = $true
      import_allowed = $false
      execution_allowed = $false
      review_milestone = "MG355"
    }
    generated_by = "skybridge-goal-append-fixture"
    generation_provider = "fixture"
    source_campaign_id = $FixtureCampaignId
    source_project_id = $ProjectId
    goal_budget_remaining = 1
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
    "# $FixtureTitle",
    "",
    "## Context",
    "This fixture candidate exists only for MG355 review and append validation.",
    "",
    "## Mission",
    "Append one reviewed generated goal as non-executed campaign metadata.",
    "",
    "## Hard Safety Boundaries",
    "- Do not execute the appended step.",
    "- Do not create or claim tasks.",
    "- Do not start a worker loop or queue runner.",
    "- Do not call Codex, MATLAB, Hermes planner or MCP.",
    "- Keep token_printed=false.",
    "",
    "## Allowed Scope",
    "- Validate this candidate.",
    "- Record review state after exact approval.",
    "- Append one pending campaign step after exact append confirmation.",
    "",
    "## Forbidden Scope",
    "- No task creation.",
    "- No task claim.",
    "- No step execution.",
    "- No worker loop.",
    "- No release, tag, asset or production infrastructure mutation.",
    "",
    "## Implementation Requirements",
    "- Append exactly one metadata step and leave it pending for a future goal.",
    "",
    "## Validation Requirements",
    "- Validate metadata, hash, budget and safety sections.",
    "",
    "## CI/CD Requirements",
    "- Run fixture smokes only; do not deploy from this generated candidate.",
    "",
    "## Manual Milestone Script Requirement",
    "- Use the MG355 manual M5 script to review, approve, preview and append.",
    "",
    "## Evidence Requirements",
    "- Report candidate hash, reviewed hash, appended step id and safety flags.",
    "",
    "## Final Report Requirements",
    "- Include import_performed, approval_performed, append_performed and no-execution flags.",
    "",
    "## No-Execution Statement",
    "This generated goal is appended for future review only and is not executed by MG355."
  ) -join [Environment]::NewLine
}

function Get-MetadataFromMarkdown([string]$Markdown) {
  $match = [regex]::Match($Markdown, '(?s)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { return $null }
  try {
    return ($match.Groups[1].Value | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Test-SecretLikeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]\s*\S+'
}

function Test-CandidateMarkdown {
  param([string]$Markdown, [string]$ExpectedGoalId)
  $errors = @()
  $metadata = Get-MetadataFromMarkdown $Markdown
  if ($null -eq $metadata) {
    $errors += "metadata_missing_or_invalid"
  } else {
    if ([string]$metadata.schema -ne $MetadataSchema) { $errors += "metadata_schema_invalid" }
    if (-not (Test-SafeGoalId ([string]$metadata.goal_id))) { $errors += "metadata_goal_id_unsafe" }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedGoalId) -and [string]$metadata.goal_id -ne $ExpectedGoalId) { $errors += "goal_id_mismatch" }
    if ($metadata.human_review_required -ne $true) { $errors += "human_review_required_not_true" }
    if ($metadata.import_allowed -ne $false) { $errors += "import_allowed_not_false" }
    if ($metadata.execution_allowed -ne $false) { $errors += "execution_allowed_not_false" }
    if ($metadata.token_printed -ne $false) { $errors += "token_printed_not_false" }
    foreach ($blocked in @($metadata.blocked_task_types)) {
      if ([string]$blocked -match "(?i)production|secret|worker-loop|task-execution|release") { continue }
    }
  }
  foreach ($section in @(
      "## Context",
      "## Mission",
      "## Hard Safety Boundaries",
      "## Allowed Scope",
      "## Forbidden Scope",
      "## Implementation Requirements",
      "## Validation Requirements",
      "## CI/CD Requirements",
      "## Manual Milestone Script Requirement",
      "## Evidence Requirements",
      "## Final Report Requirements",
      "## No-Execution Statement"
    )) {
    if ($Markdown -notmatch [regex]::Escape($section)) { $errors += "missing_section:$section" }
  }
  if (Test-SecretLikeText $Markdown) { $errors += "secret_like_content" }
  [pscustomobject]@{
    metadata_valid = ($errors.Count -eq 0)
    safety_valid = ($errors.Count -eq 0)
    errors = @($errors)
    metadata = $metadata
  }
}

function Get-Candidate {
  param([ref]$Blockers)
  if ($Fixture) {
    $root = Resolve-OutputRoot
    $path = Join-Path $root "fixture/generated-goal-355-fixture.md"
    $markdown = New-FixtureCandidateMarkdown
    return [pscustomobject]@{
      path = $path
      path_safe = Convert-ToSafePath $path
      markdown = $markdown
      hash = Get-Sha256Text $markdown
      exists_on_disk = (Test-Path -LiteralPath $path -PathType Leaf)
    }
  }
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    Add-Finding $Blockers "candidate_path_required"
    return [pscustomobject]@{ path = ""; path_safe = ""; markdown = ""; hash = ""; exists_on_disk = $false }
  }
  if (Test-PathTraversal $CandidatePath) {
    Add-Finding $Blockers "candidate_path_traversal"
    return [pscustomobject]@{ path = ""; path_safe = $CandidatePath.Replace("\", "/"); markdown = ""; hash = ""; exists_on_disk = $false }
  }
  $full = Resolve-RepoPath $CandidatePath
  if (-not (Test-AllowedCandidatePath $full)) {
    Add-Finding $Blockers "candidate_path_outside_allowed_roots"
    return [pscustomobject]@{ path = $full; path_safe = Convert-ToSafePath $full; markdown = ""; hash = ""; exists_on_disk = $false }
  }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    Add-Finding $Blockers "candidate_missing"
    return [pscustomobject]@{ path = $full; path_safe = Convert-ToSafePath $full; markdown = ""; hash = ""; exists_on_disk = $false }
  }
  $markdown = Get-Content -Raw -LiteralPath $full
  [pscustomobject]@{
    path = $full
    path_safe = Convert-ToSafePath $full
    markdown = $markdown
    hash = Get-Sha256Text $markdown
    exists_on_disk = $true
  }
}

function Get-ReviewStatePath {
  Join-Path (Resolve-ReviewStateRoot) "review-state.json"
}

function New-EmptyReviewState {
  [pscustomobject]@{
    schema = "skybridge.goal_append_review_state.v1"
    reviews = @()
    token_printed = $false
  }
}

function Read-ReviewState {
  $path = Get-ReviewStatePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return New-EmptyReviewState }
  Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Write-ReviewState($State) {
  $path = Get-ReviewStatePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  $State | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-ReviewRecord($State, [string]$GeneratedGoalId) {
  @($State.reviews | Where-Object { [string]$_.generated_goal_id -eq $GeneratedGoalId } | Select-Object -First 1)[0]
}

function Set-ReviewRecord($State, $Record) {
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($item in @($State.reviews)) {
    if ([string]$item.generated_goal_id -ne [string]$Record.generated_goal_id) { $items.Add($item) | Out-Null }
  }
  $items.Add($Record) | Out-Null
  $State.reviews = @($items.ToArray())
}

function Write-ReviewedGoalCopy([string]$GoalIdValue, [string]$Markdown) {
  $root = Resolve-ReviewedGoalRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $path = Join-Path $root ($GoalIdValue + ".md")
  Set-Content -LiteralPath $path -Value $Markdown -Encoding UTF8
  Convert-ToSafePath $path
}

function Get-CampaignStatePath {
  Join-Path (Resolve-OutputRoot) "campaign-state.json"
}

function New-EmptyCampaignState([string]$CampaignIdValue) {
  [pscustomobject]@{
    schema = "skybridge.goal_append_campaign_state.v1"
    campaign_id = $CampaignIdValue
    goal_budget_remaining = [Math]::Max(0, $GoalBudgetRemaining)
    steps = @()
    task_created = $false
    task_claimed = $false
    execution_started = $false
    worker_loop_started = $false
    token_printed = $false
  }
}

function Read-CampaignState([string]$CampaignIdValue) {
  $path = Get-CampaignStatePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return New-EmptyCampaignState $CampaignIdValue }
  Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Write-CampaignState($State) {
  $path = Get-CampaignStatePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  $State | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-Ids($Metadata) {
  $campaign = if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $CampaignId } elseif ($Live) { $LiveCampaignId } elseif ($Fixture) { $FixtureCampaignId } else { "local-goal-append-355-001" }
  $goal = if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $GoalId } elseif ($Metadata -and $Metadata.goal_id) { [string]$Metadata.goal_id } elseif ($Fixture) { $FixtureGoalId } else { "" }
  $title = if ($Metadata -and $Metadata.title) { [string]$Metadata.title } elseif ($Fixture) { $FixtureTitle } else { "" }
  $step = if ($Live) { $LiveStepId } elseif ($Fixture) { $FixtureStepId } else { "appended-" + $goal + "-step" }
  [pscustomobject]@{
    campaign_id = $campaign
    generated_goal_id = $goal
    generated_goal_title = $title
    appended_step_id = $step
  }
}

function New-Evidence {
  param($Context)
  $flags = New-SafetyFlags
  $record = [ordered]@{
    schema = $EvidenceSchema
    generated_at = $Context.generated_at
    campaign_id = $Context.campaign_id
    generated_goal_id = $Context.generated_goal_id
    candidate_hash = $Context.candidate_hash
    reviewed_hash = $Context.reviewed_hash
    appended_step_id = $Context.appended_step_id
    appended_step_order = $Context.appended_step_order
    goal_budget_remaining_before = $Context.goal_budget_remaining_before
    goal_budget_remaining_after = $Context.goal_budget_remaining_after
    validation_summary_safe = $Context.validation_summary_safe
    import_performed = $Context.import_performed
    approval_performed = $Context.approval_performed
    append_performed = $Context.append_performed
  }
  foreach ($property in $flags.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function New-Result {
  param(
    [string]$GeneratedAt,
    [string]$CandidatePathSafe,
    [string]$CandidateHash,
    [string]$ExpectedHashValue,
    [bool]$HashMatches,
    $Ids,
    [bool]$MetadataValid,
    [bool]$SafetyValid,
    [bool]$HumanReviewRequired,
    [bool]$ImportAllowed,
    [bool]$ExecutionAllowed,
    [string]$ReviewState,
    [bool]$Approved,
    [bool]$Rejected,
    [string]$ApprovalReasonSafe,
    [string]$RejectReasonSafe,
    [bool]$AppendPreviewValid,
    [bool]$AppendApplied,
    [int]$AppendedStepOrder,
    [string]$AppendedStepState,
    [int]$BudgetBefore,
    [int]$BudgetAfter,
    [bool]$ImportPerformed,
    [bool]$ApprovalPerformed,
    [bool]$AppendPerformed,
    [string[]]$Blockers,
    [string[]]$Warnings
  )
  $flags = New-SafetyFlags
  $context = [pscustomobject]@{
    generated_at = $GeneratedAt
    campaign_id = $Ids.campaign_id
    generated_goal_id = $Ids.generated_goal_id
    candidate_hash = $CandidateHash
    reviewed_hash = if ($Approved -or $AppendApplied) { $CandidateHash } else { "" }
    appended_step_id = if ($AppendPreviewValid -or $AppendApplied) { $Ids.appended_step_id } else { "" }
    appended_step_order = $AppendedStepOrder
    goal_budget_remaining_before = $BudgetBefore
    goal_budget_remaining_after = $BudgetAfter
    validation_summary_safe = if ($Blockers.Count -eq 0) { "candidate validated for metadata-only review/import" } else { "candidate blocked before metadata append" }
    import_performed = $ImportPerformed
    approval_performed = $ApprovalPerformed
    append_performed = $AppendPerformed
  }
  $record = [ordered]@{
    schema = $Schema
    generated_at = $GeneratedAt
    mode = $Mode
    project_id = $ProjectId
    campaign_id = $Ids.campaign_id
    candidate_path_safe = $CandidatePathSafe
    candidate_hash = $CandidateHash
    expected_hash = $ExpectedHashValue
    hash_matches = $HashMatches
    generated_goal_id = $Ids.generated_goal_id
    generated_goal_title = $Ids.generated_goal_title
    metadata_valid = $MetadataValid
    safety_valid = $SafetyValid
    human_review_required = $HumanReviewRequired
    import_allowed = $ImportAllowed
    execution_allowed = $ExecutionAllowed
    review_state = $ReviewState
    approved = $Approved
    rejected = $Rejected
    approval_reason_safe = $ApprovalReasonSafe
    reject_reason_safe = $RejectReasonSafe
    append_preview_valid = $AppendPreviewValid
    append_applied = $AppendApplied
    appended_step_id = if ($AppendPreviewValid -or $AppendApplied) { $Ids.appended_step_id } else { "" }
    appended_step_order = $AppendedStepOrder
    appended_step_state = $AppendedStepState
    goal_budget_remaining_before = $BudgetBefore
    goal_budget_remaining_after = $BudgetAfter
    import_performed = $ImportPerformed
    approval_performed = $ApprovalPerformed
    append_performed = $AppendPerformed
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    evidence = (New-Evidence $context)
  }
  foreach ($property in $flags.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function Write-Reports($Result) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "goal-append-review.json"
  $mdPath = Join-Path $root "goal-append-review.md"
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Result | ConvertTo-Json -Depth 90 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  @(
    "# Goal Append Review Report",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- campaign_id: $($Result.campaign_id)",
    "- generated_goal_id: $($Result.generated_goal_id)",
    "- candidate_hash: $($Result.candidate_hash)",
    "- reviewed_hash: $($Result.evidence.reviewed_hash)",
    "- appended_step_id: $($Result.appended_step_id)",
    "- appended_step_state: $($Result.appended_step_state)",
    "- goal_budget_remaining_before: $($Result.goal_budget_remaining_before)",
    "- goal_budget_remaining_after: $($Result.goal_budget_remaining_after)",
    "- import_performed: $($Result.import_performed)",
    "- approval_performed: $($Result.approval_performed)",
    "- append_performed: $($Result.append_performed)",
    "- task_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- worker_loop_started: false",
    "- token_printed: false",
    "- blockers: $(@($Result.blockers) -join ', ')",
    "- warnings: $(@($Result.warnings) -join ', ')"
  ) | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$blockers = @()
$warnings = @()
$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$candidate = Get-Candidate ([ref]$blockers)
$expectedHashValue = $ExpectedHash.Trim().ToLowerInvariant()
$expectedForValidation = if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $GoalId } else { "" }
$validation = if (-not [string]::IsNullOrWhiteSpace($candidate.markdown)) {
  Test-CandidateMarkdown -Markdown $candidate.markdown -ExpectedGoalId $expectedForValidation
} else {
  [pscustomobject]@{ metadata_valid = $false; safety_valid = $false; errors = @("candidate_unavailable"); metadata = $null }
}
foreach ($errorName in @($validation.errors)) { Add-Finding ([ref]$warnings) $errorName }
if (-not $validation.metadata_valid) { Add-Finding ([ref]$blockers) "candidate_metadata_invalid" }
if (-not $validation.safety_valid) { Add-Finding ([ref]$blockers) "candidate_safety_invalid" }

$ids = Get-Ids $validation.metadata
if (-not [string]::IsNullOrWhiteSpace($ids.generated_goal_id) -and -not (Test-SafeGoalId $ids.generated_goal_id)) {
  Add-Finding ([ref]$blockers) "generated_goal_id_unsafe"
}
$hashMatches = $true
if (-not [string]::IsNullOrWhiteSpace($expectedHashValue)) {
  $hashMatches = ([string]$candidate.hash -eq $expectedHashValue)
  if (-not $hashMatches) { Add-Finding ([ref]$blockers) "candidate_hash_mismatch" }
}

$state = Read-ReviewState
$record = if (-not [string]::IsNullOrWhiteSpace($ids.generated_goal_id)) { Get-ReviewRecord -State $state -GeneratedGoalId $ids.generated_goal_id } else { $null }
$reviewState = if ($record) { [string]$record.review_state } else { "unreviewed" }
$approved = if ($record) { [bool]$record.approved } else { $false }
$rejected = if ($record) { [bool]$record.rejected } else { $false }
$approvalReasonSafe = if ($record -and $record.approval_reason_safe) { [string]$record.approval_reason_safe } else { "" }
$rejectReasonSafe = if ($record -and $record.reject_reason_safe) { [string]$record.reject_reason_safe } else { "" }

$campaignState = Read-CampaignState $ids.campaign_id
$budgetBefore = [int]$campaignState.goal_budget_remaining
$budgetAfter = $budgetBefore
$appendPreviewValid = $false
$appendApplied = $false
$appendOrder = 0
$appendState = ""
$importPerformed = $false
$approvalPerformed = $false
$appendPerformed = $false

if ($Command -eq "approve") {
  if ($Confirm -ne $ApproveConfirmation) { Add-Finding ([ref]$blockers) "missing_approve_confirmation" }
  if ([string]::IsNullOrWhiteSpace($ApprovalReason)) { Add-Finding ([ref]$blockers) "approval_reason_required" }
  if ($blockers.Count -eq 0) {
    if ($Fixture) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $candidate.path) | Out-Null
      Set-Content -LiteralPath $candidate.path -Value $candidate.markdown -Encoding UTF8
    }
    $reviewedPath = Write-ReviewedGoalCopy -GoalIdValue $ids.generated_goal_id -Markdown $candidate.markdown
    $record = [pscustomobject]@{
      generated_goal_id = $ids.generated_goal_id
      generated_goal_title = $ids.generated_goal_title
      candidate_path_safe = $candidate.path_safe
      candidate_hash = $candidate.hash
      reviewed_hash = $candidate.hash
      reviewed_goal_path_safe = $reviewedPath
      review_state = "approved"
      approved = $true
      rejected = $false
      approval_reason_safe = Sanitize-Reason $ApprovalReason
      reject_reason_safe = ""
      reviewed_at = $generatedAt
      token_printed = $false
    }
    Set-ReviewRecord -State $state -Record $record
    Write-ReviewState $state
    $reviewState = "approved"
    $approved = $true
    $rejected = $false
    $approvalReasonSafe = [string]$record.approval_reason_safe
    $rejectReasonSafe = ""
    $importPerformed = $true
    $approvalPerformed = $true
  }
} elseif ($Command -eq "reject") {
  if ([string]::IsNullOrWhiteSpace($RejectReason)) { Add-Finding ([ref]$blockers) "reject_reason_required" }
  if ($blockers.Count -eq 0) {
    $record = [pscustomobject]@{
      generated_goal_id = $ids.generated_goal_id
      generated_goal_title = $ids.generated_goal_title
      candidate_path_safe = $candidate.path_safe
      candidate_hash = $candidate.hash
      reviewed_hash = ""
      reviewed_goal_path_safe = ""
      review_state = "rejected"
      approved = $false
      rejected = $true
      approval_reason_safe = ""
      reject_reason_safe = Sanitize-Reason $RejectReason
      reviewed_at = $generatedAt
      token_printed = $false
    }
    Set-ReviewRecord -State $state -Record $record
    Write-ReviewState $state
    $reviewState = "rejected"
    $approved = $false
    $rejected = $true
    $rejectReasonSafe = [string]$record.reject_reason_safe
  }
} elseif ($Command -in @("append-preview", "append-apply")) {
  if ($Live) {
    Add-Finding ([ref]$blockers) "live_append_endpoint_missing"
  }
  if (-not $approved) { Add-Finding ([ref]$blockers) "candidate_not_approved" }
  if ($budgetBefore -lt 1) { Add-Finding ([ref]$blockers) "goal_budget_exhausted" }
  $existing = @($campaignState.steps | Where-Object { [string]$_.generated_goal_id -eq $ids.generated_goal_id -or [string]$_.step_id -eq $ids.appended_step_id })
  if ($existing.Count -gt 0) { Add-Finding ([ref]$blockers) "step_already_appended" }
  if ($Command -eq "append-apply") {
    if ($Confirm -ne $AppendConfirmation) { Add-Finding ([ref]$blockers) "missing_append_confirmation" }
    if ([string]::IsNullOrWhiteSpace($AppendReason)) { Add-Finding ([ref]$blockers) "append_reason_required" }
  }
  if ($blockers.Count -eq 0) {
    $appendPreviewValid = $true
    $appendOrder = @($campaignState.steps).Count + 1
    $appendState = "pending"
    if ($Command -eq "append-apply") {
      $step = [pscustomobject]@{
        step_id = $ids.appended_step_id
        order = $appendOrder
        state = $appendState
        generated_goal_id = $ids.generated_goal_id
        generated_goal_title = $ids.generated_goal_title
        candidate_hash = $candidate.hash
        reviewed_hash = $candidate.hash
        append_reason_safe = Sanitize-Reason $AppendReason
        task_created = $false
        task_claimed = $false
        execution_started = $false
        worker_loop_started = $false
        token_printed = $false
      }
      $campaignState.steps = @(@($campaignState.steps) + @($step))
      $campaignState.goal_budget_remaining = $budgetBefore - 1
      Write-CampaignState $campaignState
      $record.review_state = "appended"
      Set-ReviewRecord -State $state -Record $record
      Write-ReviewState $state
      $reviewState = "appended"
      $budgetAfter = $budgetBefore - 1
      $appendApplied = $true
      $appendPerformed = $true
      $importPerformed = $true
    }
  }
} elseif ($Command -eq "report") {
  $WriteReport = $true
}

if (-not $appendApplied) {
  $budgetAfter = $budgetBefore
}
if ($Command -in @("status", "review-preview", "validate-candidate", "report", "safe-summary")) {
  # read-only commands stop after validation and current review state inspection.
}

$result = New-Result `
  -GeneratedAt $generatedAt `
  -CandidatePathSafe $candidate.path_safe `
  -CandidateHash $candidate.hash `
  -ExpectedHashValue $expectedHashValue `
  -HashMatches:$hashMatches `
  -Ids $ids `
  -MetadataValid:$validation.metadata_valid `
  -SafetyValid:$validation.safety_valid `
  -HumanReviewRequired:($validation.metadata -and $validation.metadata.human_review_required -eq $true) `
  -ImportAllowed:($validation.metadata -and $validation.metadata.import_allowed -eq $true) `
  -ExecutionAllowed:($validation.metadata -and $validation.metadata.execution_allowed -eq $true) `
  -ReviewState $reviewState `
  -Approved:$approved `
  -Rejected:$rejected `
  -ApprovalReasonSafe $approvalReasonSafe `
  -RejectReasonSafe $rejectReasonSafe `
  -AppendPreviewValid:$appendPreviewValid `
  -AppendApplied:$appendApplied `
  -AppendedStepOrder $appendOrder `
  -AppendedStepState $appendState `
  -BudgetBefore $budgetBefore `
  -BudgetAfter $budgetAfter `
  -ImportPerformed:$importPerformed `
  -ApprovalPerformed:$approvalPerformed `
  -AppendPerformed:$appendPerformed `
  -Blockers:$blockers `
  -Warnings:$warnings

if ($WriteReport) {
  Write-Reports $result
}

if ($Json) {
  ConvertTo-SafeJson $result
} elseif ($Command -eq "safe-summary") {
  Write-Host "mode=$($result.mode) generated_goal_id=$($result.generated_goal_id) review_state=$($result.review_state) appended=$($result.append_performed) blockers=$(@($result.blockers).Count) token_printed=false"
} else {
  Write-Host "SkyBridge goal append $($result.mode): review_state=$($result.review_state) appended=$($result.append_performed) token_printed=false"
}
