[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("review-queue", "validate-draft", "approve-preview", "approve-apply", "reject-preview", "reject-apply", "edit-preview", "edit-apply", "supersede-preview", "supersede-apply", "import-preview", "import-apply", "safe-summary", "attention-events")]
  [string]$Command,
  [string]$ProposedDir = "goals/proposed",
  [string]$DraftPath,
  [string]$ReviewStatePath = ".agent/tmp/goal-draft-review/review-state.json",
  [string]$ImportRoot = "goals/reviewed",
  [string]$Reviewer = "local-operator",
  [string]$Reason,
  [string]$EditText,
  [string]$SupersededBy,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$requiredSections = @(
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
$allowedTaskTypes = @("docs", "local-smoke", "refactor", "frontend", "backend", "test", "super-goal", "patch-goal", "recovery-goal", "dashboard-control-goal", "worker-service-goal", "generated-proposed-goal")
$blockedTaskTypes = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "task_execute", "codex_execute", "arbitrary_shell", "auto_execution")
$hardBlockedPhrases = @("production deploy", "deploy to production", "secret rotation", "rotate secrets", "server root", "server-root", "github settings", "branch protection", "rm -rf", "docker system prune", "auto-import", "auto import", "auto-execution", "auto execute", "approve itself", "self-approval")

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function ConvertTo-Array {
  param($Value)
  @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function ShortPath {
  param([string]$Path)
  $root = Get-RepoRoot
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  return $Path.Replace("\", "/")
}

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function Assert-UnderRoot {
  param([string]$Path, [string]$Root, [string]$Label)
  $full = [System.IO.Path]::GetFullPath($Path)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
  if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label must stay under $(ShortPath $rootFull)."
  }
  return $full
}

function Get-ProposedRoot {
  $root = Resolve-RepoPath $ProposedDir
  if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
  return (Resolve-Path -LiteralPath $root).Path
}

function Resolve-DraftPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Command requires -DraftPath." }
  $full = Resolve-RepoPath $Path
  Assert-UnderRoot -Path $full -Root (Get-ProposedRoot) -Label "Draft path"
}

function Get-MetadataFromMarkdown {
  param([string]$Markdown)
  $match = [regex]::Match($Markdown, '(?s)## Metadata\s*```json\s*(.*?)\s*```')
  if (-not $match.Success) { return $null }
  return $match.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match "(?i)(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]\s*\S+|raw_stdout|raw_stderr|raw_prompt|raw_worker_log)"
}

function Get-BlockedReasons {
  param([string]$Text)
  $reasons = New-Object System.Collections.Generic.List[string]
  foreach ($phrase in $hardBlockedPhrases) {
    if ($Text -match [regex]::Escape($phrase)) { $reasons.Add($phrase.Replace(" ", "_").Replace("-", "_")) | Out-Null }
  }
  if (Test-SecretLookingText $Text) { $reasons.Add("secret_like_content") | Out-Null }
  @($reasons.ToArray() | Select-Object -Unique)
}

function Test-Draft {
  param([string]$Path)
  $markdown = Get-Content -Raw -LiteralPath $Path
  $errors = New-Object System.Collections.Generic.List[string]
  foreach ($section in $requiredSections) {
    if ($markdown -notmatch [regex]::Escape($section)) { $errors.Add("missing_section:$section") | Out-Null }
  }
  $metadata = $null
  try { $metadata = Get-MetadataFromMarkdown $markdown } catch { $errors.Add("metadata_json_invalid") | Out-Null }
  if (-not $metadata) {
    $errors.Add("missing_metadata_json") | Out-Null
  } else {
    foreach ($field in @("proposed_goal_id", "proposed_markdown_path", "review_status", "safety_classification", "content_hash", "suggested_order", "suggested_dependencies", "allowed_task_types", "blocked_task_types", "generated_at", "token_printed")) {
      if (-not $metadata.PSObject.Properties[$field]) { $errors.Add("missing_metadata_field:$field") | Out-Null }
    }
    if ($metadata.token_printed -ne $false) { $errors.Add("metadata_token_printed_not_false") | Out-Null }
    foreach ($type in ConvertTo-Array $metadata.allowed_task_types) {
      if ($allowedTaskTypes -notcontains $type) { $errors.Add("invalid_allowed_task_type:$type") | Out-Null }
    }
    foreach ($type in ConvertTo-Array $metadata.blocked_task_types) {
      if ($blockedTaskTypes -notcontains $type) { $errors.Add("invalid_blocked_task_type:$type") | Out-Null }
    }
    foreach ($required in @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution")) {
      if ((ConvertTo-Array $metadata.blocked_task_types) -notcontains $required) { $errors.Add("missing_blocked_task_type:$required") | Out-Null }
    }
  }
  if ($markdown -notmatch "token_printed\s*=\s*false") { $errors.Add("missing_token_printed_false") | Out-Null }
  $blockedReasons = @(Get-BlockedReasons $markdown)
  $risk = if ($metadata -and $metadata.safety_classification) { [string]$metadata.safety_classification } else { "medium" }
  if ($blockedReasons.Count -gt 0) { $risk = "blocked" }
  [pscustomobject]@{
    ok = ($errors.Count -eq 0 -and $risk -ne "blocked")
    schema = "skybridge.goal_draft_review_validation.v1"
    proposed_markdown_path = ShortPath $Path
    metadata = $metadata
    original_hash = Get-Sha256 $markdown
    risk_level = $risk
    safety_classification = $risk
    blocked_reasons = $blockedReasons
    validation_errors = @($errors.ToArray())
    token_printed = $false
  }
}

function New-EmptyState {
  [pscustomobject]@{
    schema = "skybridge.goal_draft_review_state.v1"
    reviews = @()
    audit = @()
    token_printed = $false
  }
}

function Read-State {
  $path = Resolve-RepoPath $ReviewStatePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return New-EmptyState }
  Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Write-State {
  param($State)
  $path = Resolve-RepoPath $ReviewStatePath
  New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
  $State | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-ReviewRecord {
  param($State, [string]$DraftId)
  @($State.reviews | Where-Object { $_.draft_id -eq $DraftId -or $_.proposed_goal_id -eq $DraftId } | Select-Object -First 1)[0]
}

function Set-ReviewRecord {
  param($State, $Record)
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($item in @($State.reviews)) {
    if ($item.draft_id -ne $Record.draft_id) { $list.Add($item) | Out-Null }
  }
  $list.Add($Record) | Out-Null
  $State.reviews = @($list.ToArray() | Sort-Object proposed_goal_id)
}

function Add-Audit {
  param($State, [string]$Action, $Record, [string]$ReasonText)
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($item in @($State.audit)) { $items.Add($item) | Out-Null }
  $items.Add([pscustomobject]@{
    audit_id = "goal_draft_review_$($Action)_$($Record.proposed_goal_id)_20260608".Replace("-", "_")
    action = $Action
    reviewer = $Reviewer
    proposed_goal_id = $Record.proposed_goal_id
    decision_reason = $ReasonText
    reviewed_at = "2026-06-08T00:00:00.000Z"
    imported = $false
    executed = $false
    task_created = $false
    token_printed = $false
  }) | Out-Null
  $State.audit = @($items.ToArray())
}

function New-ReviewRecordFromValidation {
  param($Validation, [string]$Status)
  $m = $Validation.metadata
  $id = if ($m) { [string]$m.proposed_goal_id } else { (Split-Path -LeafBase $Validation.proposed_markdown_path) }
  [pscustomobject]@{
    draft_id = $id
    proposed_goal_id = $id
    proposed_markdown_path = $Validation.proposed_markdown_path
    review_status = $Status
    reviewer = $Reviewer
    decision = $null
    decision_reason = $null
    risk_level = $Validation.risk_level
    safety_classification = $Validation.safety_classification
    original_hash = if ($m -and $m.content_hash) { [string]$m.content_hash } else { $Validation.original_hash }
    edited_hash = $null
    import_status = "not_imported"
    import_target = $null
    import_preview = $null
    generated_at = if ($m -and $m.generated_at) { [string]$m.generated_at } else { $null }
    reviewed_at = $null
    blocked_reasons = @($Validation.blocked_reasons)
    validation_errors = @($Validation.validation_errors)
    token_printed = $false
  }
}

function Get-QueueItems {
  $state = Read-State
  @(Get-ChildItem -LiteralPath (Get-ProposedRoot) -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $validation = Test-Draft $_.FullName
    $id = if ($validation.metadata) { [string]$validation.metadata.proposed_goal_id } else { $_.BaseName }
    $record = Get-ReviewRecord -State $state -DraftId $id
    if ($record) { $record } else { New-ReviewRecordFromValidation -Validation $validation -Status ([string]$validation.metadata.review_status) }
  })
}

function Assert-Reason {
  if ([string]::IsNullOrWhiteSpace($Reason)) { throw "$Command requires -Reason." }
}

function Get-TargetPath {
  param($Validation)
  $id = [string]$Validation.metadata.proposed_goal_id
  $root = Resolve-RepoPath $ImportRoot
  $file = Join-Path $root "$id.md"
  Assert-UnderRoot -Path $file -Root $root -Label "Import target path"
}

function Get-ImportManifestPath {
  $root = Resolve-RepoPath $ImportRoot
  Assert-UnderRoot -Path (Join-Path $root "manifest.skybridge-goal-import.json") -Root $root -Label "Import manifest path"
}

function Get-ImportEntries {
  $manifestPath = Get-ImportManifestPath
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return @() }
  @((Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).goals)
}

function Test-ImportManifest {
  param($NewEntry)
  $entries = @(@(Get-ImportEntries) + @($NewEntry))
  $errors = New-Object System.Collections.Generic.List[string]
  $ids = @{}
  $orders = @{}
  foreach ($entry in $entries) {
    if ($ids.ContainsKey([string]$entry.goal_id)) { $errors.Add("duplicate_goal_id:$($entry.goal_id)") | Out-Null } else { $ids[[string]$entry.goal_id] = $true }
    if ($orders.ContainsKey([string]$entry.order)) { $errors.Add("duplicate_order:$($entry.order)") | Out-Null } else { $orders[[string]$entry.order] = $true }
    foreach ($dep in ConvertTo-Array $entry.dependencies) {
      if (-not $ids.ContainsKey($dep) -and $dep -ne "super-200-controlled-goal-draft-review-import") { $errors.Add("missing_dependency:$($entry.goal_id):$dep") | Out-Null }
    }
  }
  [pscustomobject]@{
    ok = ($errors.Count -eq 0)
    duplicate_goal_id = @($errors.ToArray() | Where-Object { $_ -match "^duplicate_goal_id" }).Count -gt 0
    duplicate_order = @($errors.ToArray() | Where-Object { $_ -match "^duplicate_order" }).Count -gt 0
    missing_dependencies = @($errors.ToArray() | Where-Object { $_ -match "^missing_dependency" })
    dependency_cycles = @()
    validation_errors = @($errors.ToArray())
    token_printed = $false
  }
}

function New-ImportPreview {
  param($Record, $Validation)
  $target = Get-TargetPath $Validation
  $m = $Validation.metadata
  $entry = [pscustomobject]@{
    goal_id = [string]$m.proposed_goal_id
    order = [int]$m.suggested_order
    path = ShortPath $target
    dependencies = @(ConvertTo-Array $m.suggested_dependencies)
    markdown_hash = $Validation.original_hash
    execution_review_required = $true
  }
  $manifestValidation = Test-ImportManifest -NewEntry $entry
  [pscustomobject]@{
    schema = "skybridge.goal_draft_import_preview.v1"
    ok = $false
    proposed_goal_id = $Record.proposed_goal_id
    mode = "dry-run"
    import_target = ShortPath $target
    manifest_path = ShortPath (Get-ImportManifestPath)
    metadata_diff = @{
      review_status = "$($Record.review_status) -> imported"
      import_status = "$($Record.import_status) -> imported"
      original_hash = $Record.original_hash
      edited_hash = $Record.edited_hash
      target_hash = $Validation.original_hash
    }
    dependency_order_changes = @{
      order = [int]$m.suggested_order
      dependencies = @(ConvertTo-Array $m.suggested_dependencies)
    }
    manifest_changes = @{
      added_goals = @($entry.goal_id)
      changed_goals = @()
      removed_goals = @()
    }
    validation = $manifestValidation
    blockers = @($Record.blocked_reasons + $Record.validation_errors + $manifestValidation.validation_errors | Where-Object { $_ })
    would_import = $true
    executed = $false
    task_created = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    token_printed = $false
  }
}

function Write-Import {
  param($Preview, [string]$SourcePath)
  $target = Resolve-RepoPath $Preview.import_target
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  Copy-Item -LiteralPath $SourcePath -Destination $target -Force
  $manifestPath = Get-ImportManifestPath
  $entries = @(@(Get-ImportEntries) + @([pscustomobject]@{
    goal_id = $Preview.proposed_goal_id
    order = [int]$Preview.dependency_order_changes.order
    path = $Preview.import_target
    dependencies = @($Preview.dependency_order_changes.dependencies)
    markdown_hash = [string]$Preview.metadata_diff.target_hash
    execution_review_required = $true
  }))
  $manifest = [pscustomobject]@{
    schema = "skybridge.reviewed_goal_import_manifest.v1"
    import_status = "staged_review_required"
    goals = @($entries | Sort-Object order, goal_id)
    no_execution_statement = "Reviewed/imported proposed goals are staged only and require a separate future execution approval."
    task_created = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    token_printed = $false
  }
  $manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

$result = $null
switch ($Command) {
  "review-queue" {
    $items = @(Get-QueueItems)
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.goal_draft_review_queue.v1"
      proposed_goal_count = $items.Count
      pending_review_count = @($items | Where-Object { $_.review_status -in @("proposed", "needs_review", "edited") }).Count
      approved_count = @($items | Where-Object { $_.review_status -eq "approved" }).Count
      rejected_count = @($items | Where-Object { $_.review_status -eq "rejected" }).Count
      imported_count = @($items | Where-Object { $_.review_status -eq "imported" }).Count
      blocked_draft_count = @($items | Where-Object { $_.safety_classification -eq "blocked" -or @($_.blocked_reasons).Count -gt 0 }).Count
      reviews = $items
      executed = $false
      task_created = $false
      worker_loop_started = $false
      token_printed = $false
    }
  }
  "validate-draft" {
    $path = Resolve-DraftPath $DraftPath
    $validation = Test-Draft $path
    $result = [pscustomobject]@{ ok = $validation.ok; schema = $validation.schema; validation = $validation; executed = $false; token_printed = $false }
  }
  { $_ -in @("approve-preview", "reject-preview", "edit-preview", "supersede-preview") } {
    $path = Resolve-DraftPath $DraftPath
    $validation = Test-Draft $path
    $status = if ($Command -eq "approve-preview") { "approved" } elseif ($Command -eq "reject-preview") { "rejected" } elseif ($Command -eq "supersede-preview") { "superseded" } else { "edited" }
    $blocked = ($Command -eq "approve-preview" -and (-not $validation.ok -or $validation.risk_level -eq "blocked"))
    $requiresReason = $Command -ne "edit-preview"
    $result = [pscustomobject]@{
      ok = (-not $blocked)
      schema = "skybridge.goal_draft_review_decision_preview.v1"
      mode = "dry-run"
      proposed_goal_id = [string]$validation.metadata.proposed_goal_id
      would_review_status = if ($blocked) { "needs_review" } else { $status }
      requires_reason = $requiresReason
      reason_present = -not [string]::IsNullOrWhiteSpace($Reason)
      blocked_reasons = if ($blocked) { @($validation.blocked_reasons + $validation.validation_errors) } else { @() }
      validation = $validation
      would_mutate = $false
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      token_printed = $false
    }
  }
  { $_ -in @("approve-apply", "reject-apply", "edit-apply", "supersede-apply") } {
    if ($Command -ne "edit-apply") { Assert-Reason }
    $path = Resolve-DraftPath $DraftPath
    $markdown = Get-Content -Raw -LiteralPath $path
    if ($Command -eq "edit-apply") {
      if ([string]::IsNullOrWhiteSpace($EditText)) { throw "edit-apply requires -EditText." }
      $markdown = $markdown.TrimEnd() + "`n`n## Review Edit`n`n$EditText`n"
      Set-Content -LiteralPath $path -Value $markdown -Encoding UTF8
    }
    $validation = Test-Draft $path
    if ($Command -eq "approve-apply" -and (-not $validation.ok -or $validation.risk_level -eq "blocked")) { throw "Blocked/unsafe drafts cannot be approved for import." }
    if ($Command -eq "approve-apply" -and $validation.risk_level -in @("medium", "high") -and [string]::IsNullOrWhiteSpace($Reason)) { throw "Medium/high risk approval requires human reason." }
    $state = Read-State
    $status = if ($Command -eq "approve-apply") { "approved" } elseif ($Command -eq "reject-apply") { "rejected" } elseif ($Command -eq "supersede-apply") { "superseded" } else { "edited" }
    $record = New-ReviewRecordFromValidation -Validation $validation -Status $status
    $record.decision = $status
    $record.decision_reason = $Reason
    $record.reviewed_at = "2026-06-08T00:00:00.000Z"
    if ($Command -eq "edit-apply") { $record.edited_hash = $validation.original_hash }
    if ($Command -eq "supersede-apply") { $record | Add-Member -NotePropertyName superseded_by -NotePropertyValue $SupersededBy -Force }
    Set-ReviewRecord -State $state -Record $record
    Add-Audit -State $state -Action $status -Record $record -ReasonText $Reason
    Write-State $state
    $result = [pscustomobject]@{ ok = $true; schema = "skybridge.goal_draft_review_decision.v1"; mode = "apply"; review = $record; audit_count = @($state.audit).Count; imported = $false; executed = $false; task_created = $false; worker_loop_started = $false; token_printed = $false }
  }
  "import-preview" {
    $path = Resolve-DraftPath $DraftPath
    $validation = Test-Draft $path
    $state = Read-State
    $record = Get-ReviewRecord -State $state -DraftId ([string]$validation.metadata.proposed_goal_id)
    if (-not $record) { $record = New-ReviewRecordFromValidation -Validation $validation -Status ([string]$validation.metadata.review_status) }
    $preview = New-ImportPreview -Record $record -Validation $validation
    if ($record.review_status -ne "approved") { $preview.blockers = @($preview.blockers + "draft_not_approved") }
    $preview.ok = (@($preview.blockers).Count -eq 0)
    $result = $preview
  }
  "import-apply" {
    Assert-Reason
    $path = Resolve-DraftPath $DraftPath
    $validation = Test-Draft $path
    $state = Read-State
    $record = Get-ReviewRecord -State $state -DraftId ([string]$validation.metadata.proposed_goal_id)
    if (-not $record -or $record.review_status -ne "approved") { throw "import-apply requires an approved draft." }
    $preview = New-ImportPreview -Record $record -Validation $validation
    if (@($preview.blockers).Count -gt 0 -or -not $preview.validation.ok) { throw "import-apply blocked by validation: $(@($preview.blockers) -join '; ')" }
    Write-Import -Preview $preview -SourcePath $path
    $record.review_status = "imported"
    $record.import_status = "imported"
    $record.import_target = $preview.import_target
    $record.import_preview = $preview
    $record.decision_reason = $Reason
    $record.reviewed_at = "2026-06-08T00:00:00.000Z"
    Set-ReviewRecord -State $state -Record $record
    Add-Audit -State $state -Action "imported" -Record $record -ReasonText $Reason
    Write-State $state
    $result = [pscustomobject]@{ ok = $true; schema = "skybridge.goal_draft_import_apply.v1"; mode = "apply"; review = $record; import_preview = $preview; imported = $true; executed = $false; task_created = $false; worker_loop_started = $false; queue_execution_enabled = $false; imported_goal_requires_execution_review = $true; token_printed = $false }
  }
  "safe-summary" {
    $items = @(Get-QueueItems)
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.proposed_goal_safe_summary.v1"
      proposed_goal_count = $items.Count
      pending_review_count = @($items | Where-Object { $_.review_status -in @("proposed", "needs_review", "edited") }).Count
      approved_count = @($items | Where-Object { $_.review_status -eq "approved" }).Count
      rejected_count = @($items | Where-Object { $_.review_status -eq "rejected" }).Count
      imported_count = @($items | Where-Object { $_.review_status -eq "imported" }).Count
      blocked_draft_count = @($items | Where-Object { $_.safety_classification -eq "blocked" -or @($_.blocked_reasons).Count -gt 0 }).Count
      import_target = (ShortPath (Resolve-RepoPath $ImportRoot))
      blocked_reason = (@($items | ForEach-Object { $_.blocked_reasons }) | Select-Object -First 1)
      next_action = "review proposed goals in Goal 200"
      imported = $false
      executed = $false
      task_created = $false
      worker_loop_started = $false
      token_printed = $false
    }
  }
  "attention-events" {
    $summary = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Command safe-summary -ProposedDir $ProposedDir -ReviewStatePath $ReviewStatePath -ImportRoot $ImportRoot -Json | ConvertFrom-Json
    $events = @(
      "proposed_goal_needs_review",
      "proposed_goal_approved",
      "proposed_goal_rejected",
      "proposed_goal_import_preview_ready",
      "proposed_goal_imported",
      "imported_goal_requires_execution_review",
      "unsafe_import_blocked"
    ) | ForEach-Object {
      [pscustomobject]@{
        schema = "skybridge.attention_event.v1"
        attention_event = $true
        event_type = $_
        attention_level = if ($_ -eq "unsafe_import_blocked") { "blocker" } elseif ($_ -eq "proposed_goal_needs_review") { "action_required" } else { "info" }
        message = "$_ is review/import state only; execution remains disabled."
        recommended_action = "Review proposed goal decisions; do not start queue execution."
        execution_enabled = $false
        token_printed = $false
      }
    }
    $result = [pscustomobject]@{ ok = $true; schema = "skybridge.goal_draft_review_attention.v1"; summary = $summary; attention_events = @($events); external_notification_sent = $false; executed = $false; token_printed = $false }
  }
}

if (-not $result.PSObject.Properties["token_printed"]) { $result | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force }
if ($Json) { $result | ConvertTo-Json -Depth 100 -Compress } else { $result | Format-List }
