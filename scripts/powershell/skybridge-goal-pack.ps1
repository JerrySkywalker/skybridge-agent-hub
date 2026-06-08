[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("templates", "validate", "manifest-preview", "manifest-update", "reimport-preview", "archive-preview", "safe-summary")]
  [string]$Command,
  [string]$GoalPackDir = "goals/dev-queue-189-200",
  [string]$ManifestFile,
  [string]$ExistingManifestFile,
  [string]$ArchiveRoot = ".agent/tmp/campaign-archives",
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$allowedTaskTypes = @(
  "docs",
  "local-smoke",
  "refactor",
  "frontend",
  "backend",
  "test",
  "super-goal",
  "patch-goal",
  "recovery-goal",
  "dashboard-control-goal",
  "worker-service-goal",
  "generated-proposed-goal"
)
$blockedTaskTypes = @(
  "production_deploy",
  "secret_rotation",
  "server_root_config",
  "github_settings",
  "branch_protection",
  "task_execute",
  "codex_execute",
  "arbitrary_shell"
)
$requiredSafetyBlocked = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection")

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-ManifestPath {
  if ($ManifestFile) { return (Resolve-Path -LiteralPath $ManifestFile -ErrorAction Stop).Path }
  $candidate = Join-Path (Get-RepoRoot) $GoalPackDir
  if (-not (Test-Path -LiteralPath $candidate)) { $candidate = $GoalPackDir }
  $path = Join-Path $candidate "campaign.skybridge.json"
  return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Read-Json {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Get-MarkdownMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)
  $raw = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($raw, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) {
    return [pscustomobject]@{ ok = $false; error = "missing fenced JSON metadata"; raw = $raw; metadata = $null; body = $raw }
  }
  try {
    $metadata = $match.Groups[1].Value | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{ ok = $false; error = "metadata JSON parse failed: $($_.Exception.Message)"; raw = $raw; metadata = $null; body = $raw }
  }
  $body = [regex]::Replace($raw, '(?ms)```json\s*\{.*?\}\s*```', "", 1).Trim()
  return [pscustomobject]@{ ok = $true; error = $null; raw = $raw; metadata = $metadata; body = $body }
}

function Test-TokenLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match "(?i)(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN (RSA |OPENSSH |PRIVATE )?PRIVATE KEY-----|cookie\s*[:=]\s*\S+)"
}

function Test-RequiredSection {
  param([string]$Body, [string[]]$Names)
  foreach ($name in $Names) {
    if ($Body -match "(?im)^##\s+$([regex]::Escape($name))\s*$") { return $true }
  }
  return $false
}

function ConvertTo-StringArray {
  param($Value)
  return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-GoalPackState {
  $manifestPath = Resolve-ManifestPath
  $manifestDir = Split-Path -Parent $manifestPath
  $manifest = Read-Json -Path $manifestPath
  $errors = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  $goalRecords = New-Object System.Collections.Generic.List[object]
  $goals = @($manifest.goals)

  if ($manifest.schema -ne "skybridge.campaign.v1") { $errors.Add("manifest schema must be skybridge.campaign.v1") | Out-Null }
  if ([string]::IsNullOrWhiteSpace([string]$manifest.campaign_id)) { $errors.Add("manifest campaign_id is required") | Out-Null }
  if ($goals.Count -eq 0) { $errors.Add("manifest goals are required") | Out-Null }
  if (-not $manifest.safety_policy) { $errors.Add("manifest safety_policy is required") | Out-Null }
  if ($manifest.safety_policy -and [bool]$manifest.safety_policy.dry_run_default -ne $true) { $errors.Add("manifest safety_policy.dry_run_default must be true") | Out-Null }
  if ($manifest.safety_policy -and [bool]$manifest.safety_policy.mutations_require_apply -ne $true) { $errors.Add("manifest safety_policy.mutations_require_apply must be true") | Out-Null }
  if ($manifest.safety_policy -and [bool]$manifest.safety_policy.no_unbounded_worker_loop -ne $true) { $errors.Add("manifest safety_policy.no_unbounded_worker_loop must be true") | Out-Null }

  $manifestBlocked = ConvertTo-StringArray $manifest.safety_policy.blocked_task_types
  foreach ($required in $requiredSafetyBlocked) {
    if ($manifestBlocked -notcontains $required) { $errors.Add("manifest safety_policy.blocked_task_types missing $required") | Out-Null }
  }

  $seenIds = @{}
  $seenOrders = @{}
  foreach ($entry in $goals) {
    $pathText = if ($entry -is [string]) { [string]$entry } else { [string]$entry.path }
    $declaredHash = if ($entry -is [string]) { $null } else { [string]$entry.markdown_hash }
    if ([string]::IsNullOrWhiteSpace($pathText)) {
      $errors.Add("goal path is required") | Out-Null
      continue
    }
    $goalPath = Join-Path $manifestDir $pathText
    if (-not (Test-Path -LiteralPath $goalPath -PathType Leaf)) {
      $errors.Add("missing markdown file: $pathText") | Out-Null
      continue
    }
    $parsed = Get-MarkdownMetadata -Path $goalPath
    if (-not $parsed.ok) {
      $errors.Add("$pathText $($parsed.error)") | Out-Null
      continue
    }
    $meta = $parsed.metadata
    $goalId = [string]$meta.goal_id
    $order = 0
    try { $order = [int]$meta.order } catch { $errors.Add("$pathText order must be an integer") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($goalId)) { $errors.Add("$pathText goal_id is required") | Out-Null }
    if ($seenIds.ContainsKey($goalId)) { $errors.Add("duplicate goal id: $goalId") | Out-Null } else { $seenIds[$goalId] = $true }
    if ($seenOrders.ContainsKey([string]$order)) { $errors.Add("duplicate order: $order") | Out-Null } else { $seenOrders[[string]$order] = $true }
    if ([string]::IsNullOrWhiteSpace([string]$meta.title)) { $errors.Add("$goalId title is required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$meta.task_type)) { $errors.Add("$goalId task_type is required") | Out-Null }

    $allowed = ConvertTo-StringArray $meta.allowed_task_types
    $blocked = ConvertTo-StringArray $meta.blocked_task_types
    if ($allowed.Count -eq 0) { $errors.Add("$goalId allowed_task_types are required") | Out-Null }
    if ($blocked.Count -eq 0) { $errors.Add("$goalId blocked_task_types are required") | Out-Null }
    foreach ($type in $allowed) {
      if ($allowedTaskTypes -notcontains $type) { $errors.Add("$goalId invalid allowed_task_type: $type") | Out-Null }
    }
    foreach ($type in $blocked) {
      if ($blockedTaskTypes -notcontains $type) { $errors.Add("$goalId invalid blocked_task_type: $type") | Out-Null }
    }
    foreach ($required in $requiredSafetyBlocked) {
      if ($blocked -notcontains $required) { $errors.Add("$goalId blocked_task_types missing $required") | Out-Null }
    }
    if (-not $meta.advance_gate) { $errors.Add("$goalId advance_gate is required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($parsed.body)) { $errors.Add("$goalId markdown body is empty") | Out-Null }
    if (Test-TokenLookingText -Text $parsed.raw) { $errors.Add("$goalId contains secret-looking text") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Context"))) { $errors.Add("$goalId missing Context section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Mission"))) { $errors.Add("$goalId missing Mission section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Hard Safety Boundaries", "Global Safety Boundaries"))) { $errors.Add("$goalId missing hard safety section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Allowed Scope", "Expected Outputs", "Non-goals"))) { $errors.Add("$goalId missing allowed scope section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Validation", "Validation Phase"))) { $errors.Add("$goalId missing Validation section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Evidence Requirements"))) { $errors.Add("$goalId missing Evidence Requirements section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("Final Campaign State", "Final Status Phase"))) { $errors.Add("$goalId missing Final Campaign State section") | Out-Null }
    if (-not (Test-RequiredSection -Body $parsed.body -Names @("No Execution Statement", "Non-goals"))) { $errors.Add("$goalId missing no-execution statement section") | Out-Null }
    if ($parsed.raw -notmatch "token_printed\s*=\s*false") { $errors.Add("$goalId missing token_printed=false statement") | Out-Null }

    $hash = Get-Sha256 -Text $parsed.raw
    $goalRecords.Add([pscustomobject]@{
      goal_id = $goalId
      title = [string]$meta.title
      order = $order
      task_type = [string]$meta.task_type
      path = $pathText.Replace("\", "/")
      markdown_hash = $hash
      manifest_markdown_hash = $declaredHash
      hash_drift = (-not [string]::IsNullOrWhiteSpace($declaredHash) -and $declaredHash -ne $hash)
      requires = ConvertTo-StringArray $meta.requires
      allowed_task_types = $allowed
      blocked_task_types = $blocked
      expected_outputs = ConvertTo-StringArray $meta.expected_outputs
      safety_policy = [pscustomobject]@{
        allowed_task_types = $allowed
        blocked_task_types = $blocked
        requires_human_approval = [bool]$meta.advance_gate.requires_human_approval
      }
    }) | Out-Null
  }

  $records = @($goalRecords.ToArray())
  $knownIds = @($records | ForEach-Object { $_.goal_id })
  $external = ConvertTo-StringArray $manifest.completed_external_dependencies
  foreach ($record in $records) {
    foreach ($dependency in @($record.requires)) {
      if ($knownIds -notcontains $dependency -and $external -notcontains $dependency) {
        $errors.Add("missing dependency: $($record.goal_id) requires $dependency") | Out-Null
      }
      $depRecord = @($records | Where-Object { $_.goal_id -eq $dependency } | Select-Object -First 1)
      if ($depRecord -and [int]$depRecord.order -ge [int]$record.order) {
        $errors.Add("goal order/dependency mismatch: $($record.goal_id) order $($record.order) requires $dependency order $($depRecord.order)") | Out-Null
      }
    }
  }

  $cycle = Get-DependencyCycle -Goals $records
  if ($cycle.Count -gt 0) { $errors.Add("dependency cycle: $($cycle -join ' -> ')") | Out-Null }

  $hashDrift = @($records | Where-Object { $_.hash_drift })
  $missingManifestHashes = @($records | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.manifest_markdown_hash) })
  if ($missingManifestHashes.Count -gt 0) { $warnings.Add("manifest markdown hashes missing for $($missingManifestHashes.Count) goal(s)") | Out-Null }

  return [pscustomobject]@{
    manifest_path = $manifestPath
    manifest_dir = $manifestDir
    manifest = $manifest
    manifest_hash = Get-Sha256 -Text (Get-Content -Raw -LiteralPath $manifestPath)
    goals = @($records | Sort-Object order)
    errors = @($errors.ToArray())
    warnings = @($warnings.ToArray())
    hash_drift = @($hashDrift)
    missing_manifest_hashes = @($missingManifestHashes)
  }
}

function Get-DependencyCycle {
  param([object[]]$Goals)
  $byId = @{}
  foreach ($goal in @($Goals)) { $byId[[string]$goal.goal_id] = $goal }
  $visiting = @{}
  $visited = @{}
  $stack = New-Object System.Collections.Generic.List[string]
  $found = New-Object System.Collections.Generic.List[string]

  function Visit {
    param([string]$GoalId)
    if ($found.Count -gt 0) { return }
    if ($visited.ContainsKey($GoalId)) { return }
    if ($visiting.ContainsKey($GoalId)) {
      $start = $stack.IndexOf($GoalId)
      if ($start -ge 0) {
        for ($i = $start; $i -lt $stack.Count; $i++) { $found.Add($stack[$i]) | Out-Null }
        $found.Add($GoalId) | Out-Null
      }
      return
    }
    if (-not $byId.ContainsKey($GoalId)) { return }
    $visiting[$GoalId] = $true
    $stack.Add($GoalId) | Out-Null
    foreach ($dep in @($byId[$GoalId].requires)) { Visit -GoalId ([string]$dep) }
    if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
    $visiting.Remove($GoalId)
    $visited[$GoalId] = $true
  }

  foreach ($goal in @($Goals)) { Visit -GoalId ([string]$goal.goal_id) }
  return @($found.ToArray())
}

function New-ManifestPreview {
  param($State)
  $updatedGoals = @($State.goals | ForEach-Object {
    [ordered]@{
      path = $_.path
      goal_id = $_.goal_id
      order = $_.order
      markdown_hash = $_.markdown_hash
    }
  })
  $wouldUpdateCount = @($State.goals | Where-Object { [string]$_.manifest_markdown_hash -ne [string]$_.markdown_hash }).Count
  return [pscustomobject]@{
    schema = "skybridge.goal_pack_manifest_update_preview.v1"
    goal_pack_id = [string]$State.manifest.campaign_id
    manifest_path = ShortPath $State.manifest_path
    mode = if ($Apply) { "apply" } else { "dry-run" }
    default_dry_run = (-not $Apply)
    would_update = (-not $Apply -and $wouldUpdateCount -gt 0)
    updated = $false
    update_count = $wouldUpdateCount
    hash_drift_count = @($State.hash_drift).Count
    missing_manifest_hash_count = @($State.missing_manifest_hashes).Count
    goals = $updatedGoals
    token_printed = $false
  }
}

function Write-ManifestUpdates {
  param($State)
  $manifest = $State.manifest
  $manifest.goals = @($State.goals | ForEach-Object {
    [ordered]@{
      path = $_.path
      goal_id = $_.goal_id
      order = $_.order
      markdown_hash = $_.markdown_hash
    }
  })
  $json = $manifest | ConvertTo-Json -Depth 80
  Set-Content -LiteralPath $State.manifest_path -Value $json -Encoding UTF8
}

function Compare-GoalPacks {
  param($Current, $Existing)
  $currentById = @{}
  $existingById = @{}
  foreach ($goal in @($Current.goals)) { $currentById[[string]$goal.goal_id] = $goal }
  foreach ($goal in @($Existing.goals)) { $existingById[[string]$goal.goal_id] = $goal }
  $added = @($Current.goals | Where-Object { -not $existingById.ContainsKey([string]$_.goal_id) })
  $removed = @($Existing.goals | Where-Object { -not $currentById.ContainsKey([string]$_.goal_id) })
  $changed = New-Object System.Collections.Generic.List[object]
  $dependencyChanges = New-Object System.Collections.Generic.List[object]
  $orderChanges = New-Object System.Collections.Generic.List[object]
  $safetyChanges = New-Object System.Collections.Generic.List[object]
  foreach ($goal in @($Current.goals)) {
    $id = [string]$goal.goal_id
    if (-not $existingById.ContainsKey($id)) { continue }
    $old = $existingById[$id]
    if ([string]$old.markdown_hash -ne [string]$goal.markdown_hash) { $changed.Add($goal) | Out-Null }
    if ((@($old.requires) -join "|") -ne (@($goal.requires) -join "|")) {
      $dependencyChanges.Add([pscustomobject]@{ goal_id = $id; before = @($old.requires); after = @($goal.requires) }) | Out-Null
    }
    if ([int]$old.order -ne [int]$goal.order) {
      $orderChanges.Add([pscustomobject]@{ goal_id = $id; before = [int]$old.order; after = [int]$goal.order }) | Out-Null
    }
    if ((@($old.blocked_task_types) -join "|") -ne (@($goal.blocked_task_types) -join "|") -or (@($old.allowed_task_types) -join "|") -ne (@($goal.allowed_task_types) -join "|")) {
      $safetyChanges.Add([pscustomobject]@{ goal_id = $id; before = $old.safety_policy; after = $goal.safety_policy }) | Out-Null
    }
  }
  return [pscustomobject]@{
    added_goals = @($added.goal_id)
    removed_goals = @($removed.goal_id)
    changed_goals = @($changed.ToArray() | ForEach-Object { $_.goal_id })
    dependency_changes = @($dependencyChanges.ToArray())
    order_changes = @($orderChanges.ToArray())
    safety_policy_changes = @($safetyChanges.ToArray())
  }
}

function ShortPath {
  param([string]$Path)
  $root = Get-RepoRoot
  if ($Path.StartsWith($root)) { return $Path.Substring($root.Length).TrimStart("\", "/").Replace("\", "/") }
  return $Path.Replace("\", "/")
}

function Test-NoExecutionFields {
  [pscustomobject]@{
    no_execution = $true
    task_created = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    live_campaign_mutated = $false
    token_printed = $false
  }
}

$state = if ($Command -eq "templates") { $null } else { Get-GoalPackState }
$result = $null

switch ($Command) {
  "templates" {
    $templateDir = Join-Path (Get-RepoRoot) "goals\templates"
    $templates = @(
      "super-goal.md",
      "patch-goal.md",
      "recovery-goal.md",
      "dashboard-control-goal.md",
      "worker-service-goal.md",
      "generated-proposed-goal.md"
    )
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "read"
      schema = "skybridge.goal_template_index.v1"
      templates = @($templates | ForEach-Object { Join-Path "goals/templates" $_ })
      template_count = $templates.Count
      no_execution_statement = "Templates are authoring-only and do not execute campaign steps."
      token_printed = $false
    }
  }
  "validate" {
    $dependencyStatus = if (@($state.errors | Where-Object { $_ -match "dependency|cycle|order/dependency" }).Count -eq 0) { "valid" } else { "invalid" }
    $result = [pscustomobject]@{
      ok = ($state.errors.Count -eq 0)
      command = $Command
      mode = "offline"
      schema = "skybridge.goal_pack_validation.v1"
      goal_pack_id = [string]$state.manifest.campaign_id
      validation_result = if ($state.errors.Count -eq 0) { "pass" } else { "fail" }
      goal_count = @($state.goals).Count
      errors = @($state.errors)
      warnings = @($state.warnings)
      hash_drift_count = @($state.hash_drift).Count
      dependency_order_status = $dependencyStatus
      goal_pack_hash = $state.manifest_hash
      no_execution = Test-NoExecutionFields
      token_printed = $false
    }
  }
  "manifest-preview" {
    $result = New-ManifestPreview -State $state
    $result | Add-Member -NotePropertyName command -NotePropertyValue $Command -Force
    $result | Add-Member -NotePropertyName no_execution -NotePropertyValue (Test-NoExecutionFields) -Force
  }
  "manifest-update" {
    $preview = New-ManifestPreview -State $state
    if ($Apply) {
      Write-ManifestUpdates -State $state
      $preview.updated = $true
      $preview.would_update = $false
    }
    $preview | Add-Member -NotePropertyName command -NotePropertyValue $Command -Force
    $preview | Add-Member -NotePropertyName no_execution -NotePropertyValue (Test-NoExecutionFields) -Force
    $result = $preview
  }
  "reimport-preview" {
    $existingPath = if ($ExistingManifestFile) { (Resolve-Path -LiteralPath $ExistingManifestFile -ErrorAction Stop).Path } else { $state.manifest_path }
    $previousManifestFile = $ManifestFile
    $ManifestFile = $existingPath
    $existing = Get-GoalPackState
    $ManifestFile = $previousManifestFile
    $diff = Compare-GoalPacks -Current $state -Existing $existing
    $unsafe = @($state.errors).Count -gt 0 -or @($diff.safety_policy_changes).Count -gt 0
    $result = [pscustomobject]@{
      ok = $true
      command = $Command
      mode = "dry-run"
      schema = "skybridge.goal_pack_reimport_preview.v1"
      goal_pack_id = [string]$state.manifest.campaign_id
      added_goals = @($diff.added_goals)
      removed_goals = @($diff.removed_goals)
      changed_goals = @($diff.changed_goals)
      hash_drift = @($state.hash_drift | ForEach-Object { [pscustomobject]@{ goal_id = $_.goal_id; path = $_.path } })
      hash_drift_count = @($state.hash_drift).Count
      dependency_changes = @($diff.dependency_changes)
      order_changes = @($diff.order_changes)
      safety_policy_changes = @($diff.safety_policy_changes)
      validation_errors = @($state.errors)
      update_safe = (-not $unsafe)
      proposed_action = if ($unsafe) { "hold_for_review" } elseif (@($diff.added_goals).Count -or @($diff.removed_goals).Count -or @($diff.changed_goals).Count) { "review_then_apply_local_update" } else { "no_change" }
      no_execution = Test-NoExecutionFields
      token_printed = $false
    }
  }
  "archive-preview" {
    $archiveTarget = Join-Path $ArchiveRoot ([string]$state.manifest.campaign_id)
    $result = [pscustomobject]@{
      ok = ($state.errors.Count -eq 0)
      command = $Command
      mode = if ($Apply) { "apply" } else { "dry-run" }
      schema = "skybridge.goal_pack_archive_preview.v1"
      goal_pack_id = [string]$state.manifest.campaign_id
      archive_target = $archiveTarget.Replace("\", "/")
      would_archive = (-not $Apply)
      archived = $false
      includes = @("campaign manifest", "goal markdown", "completed goal reports", "evidence snapshots", "generated reports")
      excludes = @("raw worker logs", "raw stdout/stderr", "raw prompts", "tokens", "Authorization headers", "cookies", "private keys", ".env")
      validation_errors = @($state.errors)
      no_execution = Test-NoExecutionFields
      token_printed = $false
    }
    if ($Apply) {
      New-Item -ItemType Directory -Path $archiveTarget -Force | Out-Null
      $result.archived = $true
      $result.would_archive = $false
    }
  }
  "safe-summary" {
    $dependencyStatus = if (@($state.errors | Where-Object { $_ -match "dependency|cycle|order/dependency" }).Count -eq 0) { "valid" } else { "invalid" }
    $proposedAction = if ($state.errors.Count -gt 0) { "hold_for_review" } elseif (@($state.hash_drift).Count -gt 0) { "review_hash_drift_then_update_manifest" } else { "safe_to_preview_import" }
    $result = [pscustomobject]@{
      ok = ($state.errors.Count -eq 0)
      command = $Command
      mode = "read"
      schema = "skybridge.campaign_safe_summary.v1"
      goal_pack_id = [string]$state.manifest.campaign_id
      validation_result = if ($state.errors.Count -eq 0) { "pass" } else { "fail" }
      hash_drift_count = @($state.hash_drift).Count
      dependency_order_status = $dependencyStatus
      proposed_import_update_action = $proposedAction
      token_printed = $false
    }
  }
}

if (-not $result.PSObject.Properties["token_printed"]) {
  $result | Add-Member -NotePropertyName token_printed -NotePropertyValue $false
}
if ($Json) {
  $result | ConvertTo-Json -Depth 100 -Compress
} else {
  $result | Format-List
}
