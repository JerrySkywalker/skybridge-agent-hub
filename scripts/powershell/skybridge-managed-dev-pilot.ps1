[CmdletBinding()]
param(
  [ValidateSet("status", "preview", "apply-fixture", "apply-local", "create-pr-preview", "create-draft-pr", "ci-status", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/managed-dev-pilot",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "managed-dev-fixture-campaign-357",
  [string]$GoalId = "managed-dev-docs-smoke-goal-357-fixture",
  [string]$BranchName = "codex/mega-357-managed-dev-pr-pilot-fixture",
  [string]$BaseBranch = "main",
  [string]$PrTitle = "MG357 Managed Development PR Pilot",
  [string]$PrBodyPath = "",
  [ValidateSet("docs-note-and-smoke-fixture", "docs-note-local", "forbidden-path-fixture", "too-many-files-fixture")]
  [string]$ChangeKind = "docs-note-and-smoke-fixture",
  [switch]$Fixture,
  [switch]$Local,
  [string]$Confirm = "",
  [switch]$NoPR,
  [switch]$ObserveCI,
  [int]$MaxChangedFiles = 5,
  [string[]]$AllowedPaths = @(
    "docs/orchestrator/",
    "docs/dev/",
    "scripts/powershell/smoke-managed-dev-",
    "package.json",
    "tests/fixtures/"
  )
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.managed_dev_pilot.v1"
$EvidenceSchema = "skybridge.managed_dev_pilot_evidence.v1"
$ApplyConfirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$PrConfirm = "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"

if ($Local) {
  $Fixture = $false
  $Mode = "local"
  if ($BranchName -eq "codex/mega-357-managed-dev-pr-pilot-fixture") {
    $BranchName = "codex/mega-357-managed-dev-pr-pilot"
  }
  if ($CampaignId -eq "managed-dev-fixture-campaign-357") {
    $CampaignId = "managed-dev-local-campaign-357"
  }
  if ($GoalId -eq "managed-dev-docs-smoke-goal-357-fixture") {
    $GoalId = "managed-dev-docs-smoke-goal-357-local"
  }
  if ($ChangeKind -eq "docs-note-and-smoke-fixture") {
    $ChangeKind = "docs-note-local"
  }
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
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/managed-dev-pilot"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/managed-dev-pilot."
  }
  $fullTarget
}

function Test-ConfirmContains([string]$Text, [string]$Needle) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $Text -split "[;|,\s]+" | Where-Object { $_ -eq $Needle } | Select-Object -First 1 | ForEach-Object { $true }
}

function New-SafetyFlags {
  [pscustomobject]@{
    auto_merge_enabled = $false
    merge_performed = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    deploy_mutation_requested = $false
    task_created = $false
    task_claimed = $false
    worker_loop_started = $false
    codex_generation_called = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    arbitrary_shell_enabled = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Get-PlannedChangedFiles {
  switch ($ChangeKind) {
    "forbidden-path-fixture" {
      return @(".github/workflows/deploy.yml")
    }
    "too-many-files-fixture" {
      return @(
        "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md",
        "docs/dev/MANAGED_DEV_PILOT_NOTE_1.md",
        "docs/dev/MANAGED_DEV_PILOT_NOTE_2.md",
        "docs/dev/MANAGED_DEV_PILOT_NOTE_3.md",
        "docs/dev/MANAGED_DEV_PILOT_NOTE_4.md",
        "docs/dev/MANAGED_DEV_PILOT_NOTE_5.md"
      )
    }
    "docs-note-local" {
      return @("docs/dev/MANAGED_DEV_PILOT_LOCAL_NOTE.md")
    }
    default {
      return @(
        "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md",
        "scripts/powershell/smoke-managed-dev-pilot-fixture.ps1"
      )
    }
  }
}

function Test-BranchNameSafe([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  if ($Name -match "\.\.|\\|\s|^/|/$") { return $false }
  return ($Name -match "^codex/[A-Za-z0-9._/-]+$")
}

function Test-AllowedChangedFile([string]$Path, [string[]]$Prefixes) {
  $normalized = $Path.Replace("\", "/").TrimStart("/")
  foreach ($prefix in $Prefixes) {
    $safePrefix = $prefix.Replace("\", "/").TrimStart("/")
    if ([string]::IsNullOrWhiteSpace($safePrefix)) { continue }
    if ($normalized -eq $safePrefix.TrimEnd("/")) { return $true }
    if ($safePrefix.EndsWith("/") -and $normalized.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if (-not $safePrefix.EndsWith("/") -and $normalized.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

function Test-ForbiddenChangedFile([string]$Path) {
  $normalized = $Path.Replace("\", "/").TrimStart("/")
  if ($normalized -match "(?i)^\.github/") { return $true }
  if ($normalized -match "(?i)(^|/)dockerfile$|docker-compose|deploy/|openresty|authelia|cloudflare|(^|/)dns/|(^|/)tls/|(^|/)firewall/") { return $true }
  if ($normalized -match "(?i)(^|/)\.env($|[./])|(^|/)secrets/|proxy-profile|token-file|credential") { return $true }
  if ($normalized -match "(?i)\.(msi|exe|zip|7z|tar|gz|dll|bin)$|release-assets|installer") { return $true }
  if ($normalized -match "(?i)production.*config|runtime.*config") { return $true }
  return $false
}

function Invoke-GitSafe([string[]]$Args) {
  $output = & git @Args 2>&1
  [pscustomobject]@{
    exit_code = $LASTEXITCODE
    text = (($output | Out-String).Trim())
  }
}

function Get-GitStatusSafe {
  try {
    $status = Invoke-GitSafe @("status", "--short")
    $branch = Invoke-GitSafe @("branch", "--show-current")
    [pscustomobject]@{
      available = ($status.exit_code -eq 0 -and $branch.exit_code -eq 0)
      status_short = if ($status.exit_code -eq 0) { @($status.text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }
      branch = if ($branch.exit_code -eq 0) { $branch.text } else { "" }
    }
  } catch {
    [pscustomobject]@{
      available = $false
      status_short = @()
      branch = ""
    }
  }
}

function Write-Reports($Result) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "managed-dev-pilot.json"
  $mdPath = Join-Path $root "managed-dev-pilot.md"
  ConvertTo-SafeJson $Result | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Managed Development PR Pilot",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- branch: $($Result.branch_name)",
    "- base_branch: $($Result.base_branch)",
    "- change_kind: $($Result.selected_change_kind)",
    "- changed_files: $($Result.files_changed)",
    "- draft_pr_created: $($Result.draft_pr_created)",
    "- pr_ci_status: $($Result.pr_ci_status)",
    "- held_for_human_review: $($Result.held_for_human_review)",
    "- auto_merge_enabled: false",
    "- merge_performed: false",
    "- release_created: false",
    "- tag_created: false",
    "- asset_uploaded: false",
    "- worker_loop_started: false",
    "- token_printed: false"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  ConvertTo-SafeJson $Result | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Result
}

$warnings = @()
$blockers = @()
$safety = New-SafetyFlags
$plannedFiles = @(Get-PlannedChangedFiles)
$previewOnly = ($Command -in @("status", "preview", "create-pr-preview", "ci-status", "report", "safe-summary"))
$applyConfirmed = (Test-ConfirmContains $Confirm $ApplyConfirm)
$prConfirmed = (Test-ConfirmContains $Confirm $PrConfirm)
$draftPrRequested = ($Command -in @("create-pr-preview", "create-draft-pr"))
$draftPrCreated = $false
$prNumber = 0
$prUrl = ""
$ciObserved = $ObserveCI.IsPresent -or $Command -eq "ci-status"
$ciStatus = if ($Fixture) { "simulated_skipped" } else { "unknown" }
$branchCreated = $false
$localValidationsRun = $false
$localValidationsPassed = $false
$changedFiles = @()
$filesChanged = 0

if ($Command -eq "safe-summary") {
  $WriteReport = $false
}

if ($MaxChangedFiles -gt 5 -or $MaxChangedFiles -lt 1) {
  Add-Finding ([ref]$blockers) "max_changed_files_must_be_between_1_and_5"
}

if (-not (Test-BranchNameSafe $BranchName)) {
  Add-Finding ([ref]$blockers) "unsafe_branch_name"
}

foreach ($file in $plannedFiles) {
  if (Test-ForbiddenChangedFile $file) {
    Add-Finding ([ref]$blockers) "forbidden_changed_file_path"
  }
  if (-not (Test-AllowedChangedFile $file $AllowedPaths)) {
    Add-Finding ([ref]$blockers) "changed_file_outside_allowed_paths"
  }
}

if ($plannedFiles.Count -gt $MaxChangedFiles) {
  Add-Finding ([ref]$blockers) "planned_changed_files_exceed_max"
}

if ($Command -eq "apply-fixture") {
  if (-not (Test-ConfirmContains $Confirm $ApplyConfirm)) {
    Add-Finding ([ref]$blockers) "missing_apply_confirmation"
  }
  if ($blockers.Count -eq 0) {
    $branchCreated = $true
    $changedFiles = $plannedFiles
    $filesChanged = $changedFiles.Count
    $localValidationsRun = $true
    $localValidationsPassed = $true
    Add-Finding ([ref]$warnings) "fixture_mode_no_real_branch_or_pr"
  }
}

if ($Command -eq "apply-local") {
  if (-not $applyConfirmed) {
    Add-Finding ([ref]$blockers) "missing_apply_confirmation"
  }
  $git = Get-GitStatusSafe
  if (-not $git.available) {
    Add-Finding ([ref]$blockers) "git_unavailable"
  } else {
    if ($git.branch -ne $BaseBranch) {
      Add-Finding ([ref]$blockers) "local_apply_requires_base_branch"
    }
    if (@($git.status_short).Count -gt 0) {
      Add-Finding ([ref]$blockers) "working_tree_not_clean"
    }
  }
  $existing = Invoke-GitSafe @("rev-parse", "--verify", $BranchName)
  if ($existing.exit_code -eq 0) {
    Add-Finding ([ref]$blockers) "branch_already_exists"
  }
  if ($blockers.Count -eq 0) {
    $checkout = Invoke-GitSafe @("checkout", "-b", $BranchName, $BaseBranch)
    if ($checkout.exit_code -ne 0) {
      Add-Finding ([ref]$blockers) "branch_create_failed"
    } else {
      $branchCreated = $true
      $localNote = Join-Path $RepoRoot "docs/dev/MANAGED_DEV_PILOT_LOCAL_NOTE.md"
      @(
        "# Managed Development Pilot Local Note",
        "",
        "This repository-local note was created by the MG357 managed development pilot local lane.",
        "It is a docs-only change for human review and must not enable auto-merge, release creation, task execution, or worker loops.",
        "",
        "token_printed=false"
      ) | Set-Content -LiteralPath $localNote -Encoding UTF8
      $changedFiles = $plannedFiles
      $filesChanged = $changedFiles.Count
      $localValidationsRun = $true
      $validation = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "smoke-managed-dev-pilot-fixture.ps1") 2>&1
      if ($LASTEXITCODE -eq 0) {
        $localValidationsPassed = $true
      } else {
        $localValidationsPassed = $false
        Add-Finding ([ref]$blockers) "local_validation_failed"
      }
    }
  }
}

if ($Command -eq "create-pr-preview") {
  $draftPrRequested = $true
  Add-Finding ([ref]$warnings) "draft_pr_preview_only"
}

if ($Command -eq "create-draft-pr") {
  $draftPrRequested = $true
  if (-not $prConfirmed) {
    Add-Finding ([ref]$blockers) "missing_draft_pr_confirmation"
  }
  if ($Fixture) {
    Add-Finding ([ref]$blockers) "fixture_mode_never_creates_real_pr"
  }
  if ($NoPR) {
    Add-Finding ([ref]$blockers) "no_pr_requested"
  }
  if ($blockers.Count -eq 0) {
    $git = Get-GitStatusSafe
    if (-not $git.available) {
      Add-Finding ([ref]$blockers) "git_unavailable"
    } elseif ($git.branch -ne $BranchName) {
      Add-Finding ([ref]$blockers) "draft_pr_requires_pilot_branch"
    }
  }
  if ($blockers.Count -eq 0) {
    $push = Invoke-GitSafe @("push", "-u", "origin", $BranchName)
    if ($push.exit_code -ne 0) {
      Add-Finding ([ref]$blockers) "branch_push_failed"
    }
  }
  if ($blockers.Count -eq 0) {
    $bodyPath = $PrBodyPath
    if ([string]::IsNullOrWhiteSpace($bodyPath)) {
      $bodyPath = Join-Path (Resolve-OutputRoot) "draft-pr-body.md"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bodyPath) | Out-Null
      @(
        "## Summary",
        "- MG357 managed development pilot docs-only change.",
        "",
        "## Validations",
        "- local validation must pass before review.",
        "",
        "## Safety",
        "- draft PR for human review only.",
        "- auto_merge_enabled=false",
        "- merge_performed=false",
        "- release_created=false",
        "- tag_created=false",
        "- asset_uploaded=false",
        "- token_printed=false"
      ) | Set-Content -LiteralPath $bodyPath -Encoding UTF8
    }
    $prRaw = & gh pr create --draft --base $BaseBranch --head $BranchName --title $PrTitle --body-file $bodyPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      Add-Finding ([ref]$blockers) "draft_pr_create_failed"
    } else {
      $draftPrCreated = $true
      $prUrl = (($prRaw | Out-String).Trim() -split "`r?`n" | Select-Object -Last 1)
      $viewRaw = & gh pr view $BranchName --json number,url 2>$null
      if ($LASTEXITCODE -eq 0) {
        $view = (($viewRaw | Out-String).Trim() | ConvertFrom-Json)
        $prNumber = [int]$view.number
        $prUrl = [string]$view.url
      }
    }
  }
}

if ($Command -eq "ci-status" -and -not $Fixture) {
  $viewRaw = & gh pr view $BranchName --json number,url,statusCheckRollup 2>$null
  if ($LASTEXITCODE -eq 0) {
    $view = (($viewRaw | Out-String).Trim() | ConvertFrom-Json)
    $prNumber = [int]$view.number
    $prUrl = [string]$view.url
    $checks = @($view.statusCheckRollup)
    if ($checks.Count -eq 0) {
      $ciStatus = "pending"
    } elseif (@($checks | Where-Object { $_.conclusion -eq "FAILURE" -or $_.conclusion -eq "CANCELLED" }).Count -gt 0) {
      $ciStatus = "failure"
    } elseif (@($checks | Where-Object { $_.status -ne "COMPLETED" }).Count -gt 0) {
      $ciStatus = "pending"
    } else {
      $ciStatus = "success"
    }
  } else {
    $ciStatus = "unknown"
    Add-Finding ([ref]$warnings) "pr_not_found_for_ci_status"
  }
}

if ($Command -in @("status", "preview", "report", "safe-summary", "create-pr-preview", "ci-status")) {
  if ($Command -eq "preview") {
    Add-Finding ([ref]$warnings) "preview_creates_no_mutation"
  }
  if ($Command -eq "status") {
    Add-Finding ([ref]$warnings) "status_read_only"
  }
}

$heldForHumanReview = $true
$validationSummary = if ($Fixture) {
  "fixture validations simulated"
} elseif ($localValidationsRun) {
  if ($localValidationsPassed) { "managed dev pilot local validation passed" } else { "managed dev pilot local validation did not pass" }
} else {
  "local validations not run"
}

$evidence = [pscustomobject]@{
  schema = $EvidenceSchema
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  branch_name = $BranchName
  base_branch = $BaseBranch
  changed_files = @($changedFiles)
  validation_summary_safe = $validationSummary
  draft_pr_created = $draftPrCreated
  pr_number = $prNumber
  pr_url_safe = $prUrl
  ci_status = $ciStatus
  held_for_human_review = $heldForHumanReview
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

$result = [pscustomobject]@{
  schema = $Schema
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  mode = $Mode
  project_id = $ProjectId
  campaign_id = $CampaignId
  goal_id = $GoalId
  branch_name = $BranchName
  base_branch = $BaseBranch
  selected_change_kind = $ChangeKind
  allowed_paths = @($AllowedPaths)
  max_changed_files = $MaxChangedFiles
  preview_only = $previewOnly
  apply_confirmed = $applyConfirmed
  branch_created = $branchCreated
  files_changed = $filesChanged
  changed_files = @($changedFiles)
  local_validations_run = $localValidationsRun
  local_validations_passed = $localValidationsPassed
  draft_pr_requested = $draftPrRequested
  draft_pr_created = $draftPrCreated
  pr_number = $prNumber
  pr_url_safe = $prUrl
  pr_ci_observed = $ciObserved
  pr_ci_status = $ciStatus
  held_for_human_review = $heldForHumanReview
  auto_merge_enabled = $false
  merge_performed = $false
  release_created = $false
  tag_created = $false
  asset_uploaded = $false
  deploy_mutation_requested = $false
  task_created = $false
  task_claimed = $false
  worker_loop_started = $false
  codex_generation_called = $false
  codex_run_called = $false
  matlab_run_called = $false
  hermes_run_called = $false
  mcp_run_called = $false
  arbitrary_shell_enabled = $false
  project_control_unpaused = $false
  blockers = @($blockers)
  warnings = @($warnings)
  safety_flags = $safety
  evidence = $evidence
  token_printed = $false
}

if ($WriteReport) {
  $result = Write-Reports $result
}

if ($Json) {
  ConvertTo-SafeJson $result
} else {
  Write-Host "SkyBridge managed development pilot"
  Write-Host "mode=$($result.mode)"
  Write-Host "command=$Command"
  Write-Host "branch=$($result.branch_name)"
  Write-Host "changed_files=$($result.files_changed)"
  Write-Host "draft_pr_created=$($result.draft_pr_created)"
  Write-Host "pr_ci_status=$($result.pr_ci_status)"
  Write-Host "held_for_human_review=$($result.held_for_human_review)"
  Write-Host "auto_merge_enabled=false"
  Write-Host "merge_performed=false"
  Write-Host "release_created=false"
  Write-Host "tag_created=false"
  Write-Host "asset_uploaded=false"
  Write-Host "worker_loop_started=false"
  Write-Host "token_printed=false"
  if ($result.blockers.Count -gt 0) {
    Write-Host ("blockers=" + ($result.blockers -join ","))
  }
}
