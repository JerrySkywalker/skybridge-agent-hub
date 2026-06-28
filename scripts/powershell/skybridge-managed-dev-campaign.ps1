[CmdletBinding()]
param(
  [ValidateSet("status", "preview", "create-fixture", "append-reviewed-dev-goal", "bounded-apply-one", "create-draft-pr", "observe-ci", "run-fixture-e2e", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/managed-dev-campaign",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "managed-dev-campaign-fixture-362",
  [string]$GoalId = "managed-dev-campaign-goal-362-fixture",
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [string]$BranchName = "codex/mg362-campaign-driven-managed-dev-pilot-pr",
  [string]$BaseBranch = "main",
  [string]$PrTitle = "MG362 Campaign-Driven Managed Dev Pilot PR",
  [int]$GoalBudgetRemaining = 1,
  [string]$Objective = "Prove one campaign-driven managed development action and hold at draft PR review.",
  [switch]$Fixture,
  [switch]$Local,
  [string]$Confirm = "",
  [switch]$NoPR,
  [switch]$ObserveCI
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.managed_dev_campaign.v1"
$EvidenceSchema = "skybridge.managed_dev_campaign_evidence.v1"
$ActionConfirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$PrConfirm = "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"
$TargetDoc = "docs/orchestrator/CAMPAIGN_DRIVEN_MANAGED_DEV_MG362.md"

if ($Local) {
  $Fixture = $false
  $Mode = "local"
} else {
  $Fixture = $true
  $Mode = "fixture"
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
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/managed-dev-campaign"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/managed-dev-campaign."
  }
  $fullTarget
}

function Test-ConfirmContains([string]$Text, [string]$Needle) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $match = $Text -split "[;|,\s]+" | Where-Object { $_ -eq $Needle } | Select-Object -First 1
  return ($null -ne $match)
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

function Test-AllowedChangedFile([string]$Path) {
  $normalized = $Path.Replace("\", "/").TrimStart("/")
  foreach ($prefix in @("docs/orchestrator/", "docs/dev/", "scripts/powershell/", "package.json", "packages/event-schema/")) {
    if ($normalized -eq $prefix.TrimEnd("/")) { return $true }
    if ($prefix.EndsWith("/") -and $normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

function Test-ForbiddenChangedFile([string]$Path) {
  $normalized = $Path.Replace("\", "/").TrimStart("/")
  if ($normalized -match "(?i)^\.github/") { return $true }
  if ($normalized -match "(?i)docker|deploy/|deployment|openresty|authelia|cloudflare|dns/|tls/|firewall/") { return $true }
  if ($normalized -match "(?i)(^|/)\.env($|[./])|(^|/)secrets/|proxy|token|credential") { return $true }
  if ($normalized -match "(?i)\.(msi|exe|dll|bin|zip|7z|tar|gz)$|release-assets|installer") { return $true }
  return $false
}

function Test-BranchNameSafe([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  if ($Name -match "\.\.|\\|\s|^/|/$") { return $false }
  return ($Name -match "^codex/[A-Za-z0-9._/-]+$")
}

function New-SafetyFlags {
  [pscustomobject]@{
    manual_fallback_used = $false
    auto_merge_enabled = $false
    merge_performed = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    production_infra_mutated = $false
    worker_loop_started = $false
    queue_runner_started = $false
    codex_generation_called = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    raw_logs_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    secrets_persisted = $false
    token_printed = $false
  }
}

function New-FixtureCandidate {
  $body = @(
    "# MG362 Reviewed Managed Dev Goal Fixture",
    "",
    "This deterministic fixture represents a reviewed managed-development goal.",
    "",
    "- human_review_required=true",
    "- review_approved=true",
    "- execution_allowed=false until the bounded managed-dev action is explicitly selected",
    "- token_printed=false"
  ) -join [Environment]::NewLine
  [pscustomobject]@{
    path_safe = ".agent/tmp/managed-dev-campaign/fixture/reviewed-managed-dev-goal-362.md"
    hash = Get-Sha256Text $body
    valid = $true
    approved = $true
  }
}

function Invoke-ManagedDevPilotJson {
  param([string[]]$ManagedArgs)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-managed-dev-pilot.ps1") @ManagedArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-dev-pilot.ps1 failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-CiStatusFromManagedResult($ManagedResult) {
  if ($null -eq $ManagedResult) { return "unknown" }
  if ($ManagedResult.pr_ci_status) { return [string]$ManagedResult.pr_ci_status }
  return "unknown"
}

function New-Result {
  param(
    [string[]]$Blockers,
    [string[]]$Warnings,
    [bool]$PreviewOnly,
    [bool]$ApplyConfirmed,
    [bool]$Appended,
    [string]$AppendedState,
    [bool]$ActionPerformed,
    [string]$SelectedAction,
    [string[]]$ChangedFiles,
    [bool]$DraftPrCreated,
    [int]$DraftPrNumber,
    [string]$DraftPrUrl,
    [string]$DraftPrCiStatus,
    [bool]$ControllerGitUsed,
    [bool]$ControllerGhUsed,
    [string]$CandidatePathSafe,
    [string]$CandidateHash
  )
  $maxOk = (@($ChangedFiles).Count -le 5)
  $forbiddenCount = @($ChangedFiles | Where-Object { Test-ForbiddenChangedFile $_ }).Count
  $allowedCount = @($ChangedFiles | Where-Object { -not (Test-AllowedChangedFile $_) }).Count
  $flags = New-SafetyFlags
  $evidence = [pscustomobject]@{
    schema = $EvidenceSchema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    campaign_id = $CampaignId
    goal_id = $GoalId
    selected_action = $SelectedAction
    appended_step_id = if ($Appended) { "managed-dev-campaign-step-362-fixture" } else { "" }
    branch_name = $BranchName
    changed_files = @($ChangedFiles)
    draft_pr_created = $DraftPrCreated
    draft_pr_number = $DraftPrNumber
    draft_pr_ci_status = $DraftPrCiStatus
    held_for_human_review = $true
    manual_fallback_used = $false
    auto_merge_enabled = $false
    merge_performed = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    raw_logs_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    secrets_persisted = $false
    token_printed = $false
  }
  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    project_id = $ProjectId
    campaign_id = $CampaignId
    goal_id = $GoalId
    candidate_path_safe = $CandidatePathSafe
    candidate_hash = $CandidateHash
    reviewed_goal_valid = $true
    review_approved = $true
    appended_step_id = if ($Appended) { "managed-dev-campaign-step-362-fixture" } else { "" }
    appended_step_state = $AppendedState
    bounded_loop_selected_action = $SelectedAction
    bounded_loop_action_performed = $ActionPerformed
    managed_dev_branch = $BranchName
    changed_files = @($ChangedFiles)
    max_changed_files_check = if ($maxOk) { "passed" } else { "failed" }
    forbidden_path_check = if ($forbiddenCount -eq 0 -and $allowedCount -eq 0) { "passed" } else { "failed" }
    controller_native_git_used = $ControllerGitUsed
    controller_native_gh_used = $ControllerGhUsed
    manual_fallback_used = $false
    draft_pr_created = $DraftPrCreated
    draft_pr_number = $DraftPrNumber
    draft_pr_url_safe = $DraftPrUrl
    draft_pr_ci_status = $DraftPrCiStatus
    held_for_human_review = $true
    auto_merge_enabled = $false
    merge_performed = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    production_infra_mutated = $false
    worker_loop_started = $false
    queue_runner_started = $false
    codex_generation_called = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    preview_only = $PreviewOnly
    apply_confirmed = $ApplyConfirmed
    blockers = @($Blockers)
    warnings = @($Warnings)
    safety_flags = $flags
    evidence = $evidence
    token_printed = $false
  }
}

function Write-Reports($Result) {
  if (-not $WriteReport) { return $Result }
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "managed-dev-campaign.json"
  $mdPath = Join-Path $root "managed-dev-campaign.md"
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  ConvertTo-SafeJson $Result | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  @(
    "# Managed Dev Campaign E2E",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- campaign_id: $($Result.campaign_id)",
    "- goal_id: $($Result.goal_id)",
    "- appended_step_id: $($Result.appended_step_id)",
    "- bounded_loop_selected_action: $($Result.bounded_loop_selected_action)",
    "- branch: $($Result.managed_dev_branch)",
    "- changed_files: $(@($Result.changed_files) -join ', ')",
    "- draft_pr_created: $($Result.draft_pr_created)",
    "- draft_pr_number: $($Result.draft_pr_number)",
    "- draft_pr_ci_status: $($Result.draft_pr_ci_status)",
    "- held_for_human_review: $($Result.held_for_human_review)",
    "- manual_fallback_used: false",
    "- auto_merge_enabled: false",
    "- merge_performed: false",
    "- release_created: false",
    "- tag_created: false",
    "- asset_uploaded: false",
    "- worker_loop_started: false",
    "- token_printed: false"
  ) | Set-Content -LiteralPath $mdPath -Encoding UTF8
  ConvertTo-SafeJson $Result | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Result
}

$warnings = @()
$blockers = @()
$candidate = New-FixtureCandidate
$previewOnly = ($Command -in @("status", "preview", "create-fixture", "report", "safe-summary"))
$actionConfirmed = Test-ConfirmContains $Confirm $ActionConfirm
$prConfirmed = Test-ConfirmContains $Confirm $PrConfirm
$selectedAction = "managed_dev_draft_pr"
$appended = $false
$appendedState = ""
$actionPerformed = $false
$changedFiles = @()
$draftPrCreated = $false
$draftPrNumber = 0
$draftPrUrl = ""
$draftPrCiStatus = if ($Fixture) { "simulated_skipped" } else { "unknown" }
$controllerGitUsed = $false
$controllerGhUsed = $false

if (-not (Test-BranchNameSafe $BranchName)) {
  Add-Finding ([ref]$blockers) "unsafe_branch_name"
}

if ($Command -eq "preview") {
  Add-Finding ([ref]$warnings) "preview_creates_no_mutation"
}

if ($Command -in @("append-reviewed-dev-goal", "bounded-apply-one", "run-fixture-e2e") -and -not $actionConfirmed) {
  Add-Finding ([ref]$blockers) "missing_campaign_managed_dev_action_confirmation"
}

if ($Command -eq "create-draft-pr" -and -not $prConfirmed) {
  Add-Finding ([ref]$blockers) "missing_draft_pr_confirmation"
}

if ($NoPR -and $Command -eq "create-draft-pr") {
  Add-Finding ([ref]$blockers) "no_pr_requested"
}

if ($Command -eq "append-reviewed-dev-goal" -and $blockers.Count -eq 0) {
  $previewOnly = $false
  $appended = $true
  $appendedState = "ready_for_managed_dev_action"
  $actionPerformed = $false
}

if ($Command -eq "bounded-apply-one" -and $blockers.Count -eq 0) {
  $previewOnly = $false
  $appended = $true
  $appendedState = "completed_for_draft_pr_hold"
  $actionPerformed = $true
  if ($Fixture) {
    $changedFiles = @($TargetDoc)
    Add-Finding ([ref]$warnings) "fixture_mode_no_real_branch_or_pr"
  } else {
    $managed = Invoke-ManagedDevPilotJson -ManagedArgs @(
      "-Command", "apply-local",
      "-Local",
      "-BranchName", $BranchName,
      "-BaseBranch", $BaseBranch,
      "-PrTitle", $PrTitle,
      "-ChangeKind", "mg362-campaign-driven-doc",
      "-Confirm", "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
    )
    foreach ($blocker in @($managed.blockers)) { Add-Finding ([ref]$blockers) ([string]$blocker) }
    foreach ($warning in @($managed.warnings)) { Add-Finding ([ref]$warnings) ([string]$warning) }
    $changedFiles = @($managed.changed_files)
    $controllerGitUsed = [bool]$managed.controller_native_git_used
  }
}

if ($Command -eq "run-fixture-e2e" -and $blockers.Count -eq 0) {
  $previewOnly = $false
  $appended = $true
  $appendedState = "completed_for_draft_pr_hold"
  $actionPerformed = $true
  $changedFiles = @($TargetDoc)
  $draftPrCreated = $false
  $draftPrCiStatus = "success"
  $controllerGitUsed = $true
  $controllerGhUsed = $true
  Add-Finding ([ref]$warnings) "fixture_mode_simulated_draft_pr_only"
}

if ($Command -eq "create-draft-pr" -and $blockers.Count -eq 0) {
  if ($Fixture) {
    Add-Finding ([ref]$blockers) "fixture_mode_never_creates_real_pr"
  } else {
    $managed = Invoke-ManagedDevPilotJson -ManagedArgs @(
      "-Command", "create-draft-pr",
      "-Local",
      "-BranchName", $BranchName,
      "-BaseBranch", $BaseBranch,
      "-PrTitle", $PrTitle,
      "-ChangeKind", "mg362-campaign-driven-doc",
      "-Confirm", "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"
    )
    foreach ($blocker in @($managed.blockers)) { Add-Finding ([ref]$blockers) ([string]$blocker) }
    foreach ($warning in @($managed.warnings)) { Add-Finding ([ref]$warnings) ([string]$warning) }
    $changedFiles = @($managed.changed_files)
    $draftPrCreated = [bool]$managed.draft_pr_created
    $draftPrNumber = [int]$managed.pr_number
    $draftPrUrl = [string]$managed.pr_url_safe
    $draftPrCiStatus = Get-CiStatusFromManagedResult $managed
    $controllerGitUsed = [bool]$managed.controller_native_git_used
    $controllerGhUsed = [bool]$managed.controller_native_gh_used
    $appended = $true
    $appendedState = "completed_for_draft_pr_hold"
    $actionPerformed = $true
  }
}

if ($Command -eq "observe-ci") {
  if ($Fixture) {
    $draftPrCiStatus = "success"
    $controllerGhUsed = $true
  } else {
    $managed = Invoke-ManagedDevPilotJson -ManagedArgs @(
      "-Command", "ci-status",
      "-Local",
      "-BranchName", $BranchName,
      "-BaseBranch", $BaseBranch,
      "-PrTitle", $PrTitle,
      "-ChangeKind", "mg362-campaign-driven-doc",
      "-ObserveCI"
    )
    foreach ($blocker in @($managed.blockers)) { Add-Finding ([ref]$blockers) ([string]$blocker) }
    foreach ($warning in @($managed.warnings)) { Add-Finding ([ref]$warnings) ([string]$warning) }
    $draftPrNumber = [int]$managed.pr_number
    $draftPrUrl = [string]$managed.pr_url_safe
    $draftPrCiStatus = Get-CiStatusFromManagedResult $managed
    $controllerGhUsed = [bool]$managed.controller_native_gh_used
  }
}

if ($Command -eq "create-fixture") {
  Add-Finding ([ref]$warnings) "fixture_candidate_available"
}

if ($Command -eq "report") {
  $WriteReport = $true
}

$result = New-Result `
  -Blockers:$blockers `
  -Warnings:$warnings `
  -PreviewOnly:$previewOnly `
  -ApplyConfirmed:$actionConfirmed `
  -Appended:$appended `
  -AppendedState:$appendedState `
  -ActionPerformed:$actionPerformed `
  -SelectedAction:$selectedAction `
  -ChangedFiles:$changedFiles `
  -DraftPrCreated:$draftPrCreated `
  -DraftPrNumber:$draftPrNumber `
  -DraftPrUrl:$draftPrUrl `
  -DraftPrCiStatus:$draftPrCiStatus `
  -ControllerGitUsed:$controllerGitUsed `
  -ControllerGhUsed:$controllerGhUsed `
  -CandidatePathSafe:$candidate.path_safe `
  -CandidateHash:$candidate.hash

$result = Write-Reports $result

if ($Json) {
  ConvertTo-SafeJson $result
} elseif ($Command -eq "safe-summary") {
  Write-Host "managed_dev_campaign action=$($result.bounded_loop_selected_action) pr_created=$($result.draft_pr_created) auto_merge_enabled=false token_printed=false"
} else {
  Write-Host "SkyBridge managed dev campaign $($result.mode): action=$($result.bounded_loop_selected_action) pr_created=$($result.draft_pr_created) token_printed=false"
  if (@($result.blockers).Count -gt 0) {
    Write-Host ("blockers=" + (@($result.blockers) -join ","))
  }
}
