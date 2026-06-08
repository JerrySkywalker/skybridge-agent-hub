[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("goal-draft-generate-preview", "goal-draft-generate-fixture", "goal-draft-validate", "goal-draft-list", "goal-draft-safe-summary", "goal-draft-reject-preview", "goal-draft-approve-for-import-preview")]
  [string]$Command,
  [string]$ProposedDir = "goals/proposed",
  [string]$DraftPath,
  [ValidateSet("safe", "unsafe", "medium")]
  [string]$Fixture = "safe",
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason
)

$ErrorActionPreference = "Stop"

$RequiredSections = @(
  "## Metadata",
  "## Context",
  "## Mission",
  "## Hard Safety Boundaries",
  "## Allowed Scope",
  "## Validation",
  "## Evidence Requirements",
  "## Final Campaign State",
  "## No-Execution Statement"
)

$BlockedPatterns = @(
  "production deploy",
  "deploy to production",
  "secret rotation",
  "rotate secrets",
  "server root",
  "server-root",
  "github settings",
  "branch protection",
  "credential extraction",
  "extract credentials",
  "rm -rf",
  "docker system prune",
  "unbounded worker loop",
  "auto-import",
  "auto import",
  "auto-execution",
  "auto execute",
  "approve itself",
  "self-approval"
)

$SecretPatterns = @(
  "sk-[A-Za-z0-9_-]{20,}",
  "gh[pousr]_[A-Za-z0-9_]{20,}",
  "authorization\s*[:=]\s*bearer",
  "bearer\s+[A-Za-z0-9_.-]{12,}",
  "-----BEGIN [A-Z ]*PRIVATE KEY-----",
  "password\s*[:=]\s*\S+",
  "token\s*[:=]\s*\S+"
)

function ConvertTo-Slug {
  param([string]$Text)
  $slug = $Text.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  $slug = $slug.Trim("-")
  if ([string]::IsNullOrWhiteSpace($slug)) { return "proposed-goal" }
  return $slug
}

function Get-HashText {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Test-SecretLookingText {
  param([string]$Text)
  foreach ($pattern in $SecretPatterns) {
    if ($Text -match $pattern) { return $true }
  }
  return $false
}

function Get-BlockedReasons {
  param([string]$Text)
  $reasons = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in $BlockedPatterns) {
    if ($Text -match [regex]::Escape($pattern)) { $reasons.Add($pattern.Replace(" ", "_")) | Out-Null }
  }
  return @($reasons | Select-Object -Unique)
}

function New-FixtureDraftModel {
  param([string]$Kind)
  if ($Kind -eq "unsafe") {
    return [pscustomobject]@{
      proposed_goal_id = "proposed-unsafe-production-deploy"
      title = "Unsafe Production Deployment"
      source = "fixture"
      safety_classification = "blocked"
      review_status = "needs_review"
      suggested_order = 201
      suggested_dependencies = @("super-200-controlled-goal-draft-review-import")
      allowed_task_types = @("docs")
      blocked_task_types = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution")
      expected_outputs = @("blocked_draft_record")
      review_notes = @("Fixture intentionally mentions production deploy, secret rotation, GitHub settings, branch protection, auto-import and auto-execution so the safety filter blocks it.")
      mission = "Deploy to production, rotate secrets, update GitHub settings and branch protection, auto-import the generated goal, and approve itself."
    }
  }
  if ($Kind -eq "medium") {
    return [pscustomobject]@{
      proposed_goal_id = "proposed-goal-201-notification-digest"
      title = "Goal 201 Notification Digest Review"
      source = "fixture"
      safety_classification = "medium"
      review_status = "needs_review"
      suggested_order = 201
      suggested_dependencies = @("super-200-controlled-goal-draft-review-import")
      allowed_task_types = @("docs", "local-smoke")
      blocked_task_types = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution")
      expected_outputs = @("digest_review_docs", "fixture_smokes")
      review_notes = @("Medium risk because it designs future notification routing but remains proposed and review-only.")
      mission = "Draft a review-only local notification digest goal that summarizes proposed queue attention without external sends."
    }
  }
  [pscustomobject]@{
    proposed_goal_id = "proposed-goal-201-local-readme-refresh"
    title = "Goal 201 Local README Refresh"
    source = "fixture"
    safety_classification = "low"
    review_status = "proposed"
    suggested_order = 201
    suggested_dependencies = @("super-200-controlled-goal-draft-review-import")
    allowed_task_types = @("docs", "local-smoke")
    blocked_task_types = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution")
    expected_outputs = @("reviewed_docs", "fixture_smoke")
    review_notes = @("Fixture-generated proposed goal for human review only.")
    mission = "Refresh local project documentation for the proposed-goal workflow after Goal 200 imports reviewed drafts."
  }
}

function ConvertTo-DraftMarkdown {
  param($Model)
  $bodyLines = @(
    "## Context",
    "",
    "SkyBridge may use fixture or Hermes-adapter output to draft future Super Goals, but this artifact is only a proposed goal.",
    "",
    "## Mission",
    "",
    $Model.mission,
    "",
    "## Hard Safety Boundaries",
    "",
    "- Do not import this generated goal into an active campaign.",
    "- Do not execute this generated goal.",
    "- Do not create campaign-step-derived execution tasks.",
    "- Do not allow generated goals to approve themselves.",
    "- Do not print or persist tokens, Authorization headers, raw prompts, raw LLM outputs, raw stdout/stderr, private keys, cookies, or secret-bearing local paths.",
    "- token_printed=false",
    "",
    "## Allowed Scope",
    "",
    "- Human review under goals/proposed only.",
    "- Fixture-generated Markdown may be written only with explicit fixture apply mode.",
    "- Real Hermes invocation remains disabled unless a later reviewed goal explicitly enables a fixture-safe adapter boundary.",
    "",
    "## Validation",
    "",
    "- Validate required sections before writing.",
    "- Validate safety filter classification before writing.",
    "- Validate output path remains under goals/proposed.",
    "- Validate no import, no execution, no task claim, and no worker loop.",
    "- Validate token_printed=false.",
    "",
    "## Evidence Requirements",
    "",
    "- Proposed draft path.",
    "- Stable content hash.",
    "- Safety classification and blocked reasons.",
    "- Review status.",
    "- No-import and no-execution confirmation.",
    "",
    "## Final Campaign State",
    "",
    "- Goal 199 may create proposed drafts only.",
    "- Goal 200 is required for controlled review/import.",
    "- Active campaign manifests are not updated by this draft.",
    "- token_printed=false",
    "",
    "## No-Execution Statement",
    "",
    "This generated goal is proposed/review-required only. It must not be imported, approved for import, or executed by Goal 199.",
    ""
  ) -join "`n"
  $contentHash = Get-HashText -Text $bodyLines
  $relativePath = "goals/proposed/$($Model.proposed_goal_id).md"
  $metadata = [ordered]@{
    proposed_goal_id = $Model.proposed_goal_id
    title = $Model.title
    source = $Model.source
    proposed_markdown_path = $relativePath
    content_hash = $contentHash
    safety_classification = $Model.safety_classification
    review_status = $Model.review_status
    suggested_order = $Model.suggested_order
    suggested_dependencies = @($Model.suggested_dependencies)
    allowed_task_types = @($Model.allowed_task_types)
    blocked_task_types = @($Model.blocked_task_types)
    expected_outputs = @($Model.expected_outputs)
    review_notes = @($Model.review_notes)
    generated_at = "2026-06-08T00:00:00.000Z"
    review_required = $true
    token_printed = $false
  }
  $metadataJson = $metadata | ConvertTo-Json -Depth 20
  @(
    "# $($Model.title)",
    "",
    "## Metadata",
    "",
    '```json',
    $metadataJson,
    '```',
    "",
    $bodyLines
  ) -join "`n"
}

function Get-ResolvedProposedRoot {
  $root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
  $target = Join-Path $root.Path $ProposedDir
  if (-not (Test-Path -LiteralPath $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
  }
  return (Resolve-Path -LiteralPath $target).Path
}

function Assert-UnderProposedDir {
  param([string]$Path)
  $root = Get-ResolvedProposedRoot
  $full = [System.IO.Path]::GetFullPath((Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path $Path))
  if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Draft output path must stay under $ProposedDir."
  }
  return $full
}

function Get-MetadataFromMarkdown {
  param([string]$Markdown)
  $match = [regex]::Match($Markdown, '(?s)## Metadata\s*```json\s*(.*?)\s*```')
  if (-not $match.Success) { return $null }
  return $match.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
}

function Test-DraftMarkdown {
  param([string]$Markdown)
  $errors = @()
  foreach ($section in $RequiredSections) {
    $sectionPattern = [regex]::Escape($section)
    if ($Markdown -notmatch $sectionPattern) { $errors += ("missing_section:" + $section) }
  }
  if ($Markdown -notmatch "token_printed=false") { $errors += "missing_token_printed_false" }
  $metadata = Get-MetadataFromMarkdown -Markdown $Markdown
  if (-not $metadata) {
    $errors += "missing_metadata_json"
  } else {
    foreach ($field in @("proposed_goal_id", "title", "source", "proposed_markdown_path", "content_hash", "safety_classification", "review_status", "suggested_order", "suggested_dependencies", "allowed_task_types", "blocked_task_types", "expected_outputs", "review_notes", "generated_at", "token_printed")) {
      if (-not $metadata.PSObject.Properties[$field]) { $errors += ("missing_metadata_field:" + $field) }
    }
    if ($metadata.token_printed -ne $false) { $errors += "metadata_token_printed_not_false" }
  }
  $blockedReasons = @(Get-BlockedReasons -Text $Markdown)
  $secretFound = Test-SecretLookingText -Text $Markdown
  if ($secretFound) { $errors += "secret_like_content" }
  $classification = if ($blockedReasons.Count -gt 0 -or $secretFound) { "blocked" } elseif ($metadata -and $metadata.safety_classification) { [string]$metadata.safety_classification } else { "medium" }
  $ok = ($errors.Count -eq 0 -and $classification -ne "blocked")
  [pscustomobject]@{
    ok = $ok
    schema = "skybridge.proposed_goal_validation.v1"
    metadata = $metadata
    safety_classification = $classification
    review_status = if ($metadata) { [string]$metadata.review_status } else { "needs_review" }
    blocked_reasons = @($blockedReasons)
    validation_errors = @($errors)
    required_sections_present = ($RequiredSections.Count -eq @($RequiredSections | Where-Object { $Markdown -match ([regex]::Escape($_)) }).Count)
    token_printed = $false
  }
}

function Get-ProposedDraftFiles {
  $root = Get-ResolvedProposedRoot
  @(Get-ChildItem -LiteralPath $root -Filter "*.md" -File -ErrorAction SilentlyContinue)
}

function Select-DraftListItem {
  param([System.IO.FileInfo]$File)
  $markdown = Get-Content -Raw -LiteralPath $File.FullName
  $validation = Test-DraftMarkdown -Markdown $markdown
  $metadata = $validation.metadata
  [pscustomobject]@{
    proposed_goal_id = if ($metadata) { $metadata.proposed_goal_id } else { $File.BaseName }
    title = if ($metadata) { $metadata.title } else { $File.BaseName }
    source = if ($metadata) { $metadata.source } else { "manual" }
    proposed_markdown_path = "goals/proposed/$($File.Name)"
    content_hash = if ($metadata) { $metadata.content_hash } else { Get-HashText -Text $markdown }
    safety_classification = $validation.safety_classification
    review_status = $validation.review_status
    suggested_dependencies = if ($metadata) { @($metadata.suggested_dependencies) } else { @() }
    review_notes = if ($metadata) { @($metadata.review_notes) } else { @("metadata missing") }
    blocked_reasons = @($validation.blocked_reasons)
    token_printed = $false
  }
}

function Write-GoalDraftResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) {
    $Result | ConvertTo-Json -Depth 80 -Compress
  } else {
    $Result | Format-List
  }
}

$result = $null
switch ($Command) {
  "goal-draft-generate-preview" {
    $model = New-FixtureDraftModel -Kind $Fixture
    $markdown = ConvertTo-DraftMarkdown -Model $model
    $validation = Test-DraftMarkdown -Markdown $markdown
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "dry-run"
      would_write = $false
      draft = $validation.metadata
      validation = $validation
      markdown_preview = $markdown
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      token_printed = $false
    }
  }
  "goal-draft-generate-fixture" {
    $model = New-FixtureDraftModel -Kind $Fixture
    $markdown = ConvertTo-DraftMarkdown -Model $model
    $validation = Test-DraftMarkdown -Markdown $markdown
    $path = if ($DraftPath) { $DraftPath } else { "goals/proposed/$($model.proposed_goal_id).md" }
    $fullPath = Assert-UnderProposedDir -Path $path
    if (-not $validation.ok) {
      $result = [pscustomobject]@{ ok = $false; command = $Command; mode = if ($Apply) { "apply" } else { "dry-run" }; would_write = $false; wrote = $false; validation = $validation; imported = $false; executed = $false; task_created = $false; worker_loop_started = $false; token_printed = $false }
      break
    }
    if ($Apply) {
      $markdown | Set-Content -LiteralPath $fullPath -Encoding UTF8
    }
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = if ($Apply) { "apply" } else { "dry-run" }
      would_write = (-not $Apply)
      wrote = [bool]$Apply
      proposed_markdown_path = $path.Replace("\", "/")
      full_path = $fullPath
      draft = $validation.metadata
      validation = $validation
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      campaign_manifest_updated = $false
      token_printed = $false
    }
  }
  "goal-draft-validate" {
    if ([string]::IsNullOrWhiteSpace($DraftPath)) { throw "goal-draft-validate requires -DraftPath." }
    $fullPath = Assert-UnderProposedDir -Path $DraftPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Draft not found: $DraftPath" }
    $markdown = Get-Content -Raw -LiteralPath $fullPath
    $validation = Test-DraftMarkdown -Markdown $markdown
    $result = [pscustomobject]@{ ok = $validation.ok; command = $Command; mode = "read"; proposed_markdown_path = $DraftPath.Replace("\", "/"); validation = $validation; imported = $false; executed = $false; token_printed = $false }
  }
  "goal-draft-list" {
    $items = @(Get-ProposedDraftFiles | ForEach-Object { Select-DraftListItem -File $_ })
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; proposed_goal_count = $items.Count; proposed_goals = $items; imported = $false; executed = $false; token_printed = $false }
  }
  "goal-draft-safe-summary" {
    $items = @(Get-ProposedDraftFiles | ForEach-Object { Select-DraftListItem -File $_ })
    $pending = @($items | Where-Object { $_.review_status -in @("proposed", "needs_review") })
    $blocked = @($items | Where-Object { $_.safety_classification -eq "blocked" -or @($_.blocked_reasons).Count -gt 0 })
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "read"
      schema = "skybridge.proposed_goal_safe_summary.v1"
      proposed_goal_count = $items.Count
      pending_review_count = $pending.Count
      approved_count = @($items | Where-Object { $_.review_status -in @("approved", "approved_for_import") }).Count
      rejected_count = @($items | Where-Object { $_.review_status -eq "rejected" }).Count
      imported_count = @($items | Where-Object { $_.review_status -eq "imported" }).Count
      blocked_draft_count = $blocked.Count
      import_target = "goals/reviewed"
      blocked_reason = if ($blocked.Count -gt 0) { "unsafe_import_blocked" } else { $null }
      next_action = "review proposed goals in Goal 200"
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      import_requires_goal_200 = $true
      token_printed = $false
    }
  }
  "goal-draft-reject-preview" {
    if ([string]::IsNullOrWhiteSpace($DraftPath)) { throw "goal-draft-reject-preview requires -DraftPath." }
    $fullPath = Assert-UnderProposedDir -Path $DraftPath
    $markdown = if (Test-Path -LiteralPath $fullPath -PathType Leaf) { Get-Content -Raw -LiteralPath $fullPath } else { "" }
    $validation = if ($markdown) { Test-DraftMarkdown -Markdown $markdown } else { $null }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; would_review_status = "rejected"; reason = $Reason; validation = $validation; imported = $false; executed = $false; task_created = $false; worker_loop_started = $false; token_printed = $false }
  }
  "goal-draft-approve-for-import-preview" {
    if ([string]::IsNullOrWhiteSpace($DraftPath)) { throw "goal-draft-approve-for-import-preview requires -DraftPath." }
    $fullPath = Assert-UnderProposedDir -Path $DraftPath
    $markdown = if (Test-Path -LiteralPath $fullPath -PathType Leaf) { Get-Content -Raw -LiteralPath $fullPath } else { "" }
    $validation = if ($markdown) { Test-DraftMarkdown -Markdown $markdown } else { $null }
    $blocked = ($validation -and (-not $validation.ok))
    $result = [pscustomobject]@{
      ok = (-not $blocked)
      command = $Command
      mode = "dry-run"
      would_review_status = if ($blocked) { "needs_review" } else { "approved_for_import" }
      import_requires_goal_200 = $true
      would_import = $false
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      validation = $validation
      token_printed = $false
    }
  }
}

Write-GoalDraftResult -Result $result
