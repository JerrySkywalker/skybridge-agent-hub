[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [string]$Title,
  [string]$Description,
  [string[]]$Constraints = @(),
  [string]$ConstraintsFile,
  [string]$ConstraintsJson,
  [string[]]$AcceptanceCriteria = @("Task proposals are reviewed before executable tasks are created."),
  [string[]]$StopConditions = @("Stop before any high-risk or production deployment work."),
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [ValidateSet("rule-based", "hermes-preview", "hermes-apply")]
  [string]$PlannerMode = "rule-based",
  [string]$FixtureFile,
  [ValidateSet("compact", "full")]
  [string]$StateMode = "compact",
  [int]$TimeoutSeconds = 120,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-PlanApiConfig {
  $authMode = "none"
  if ($TokenEnvVar -or $TokenFile) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Invoke-PlanApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 30
}

function New-Slug {
  param([string]$Prefix, [string]$Text)
  $slug = ($Text.ToLowerInvariant() -replace "[^a-z0-9]+", "-" -replace "^-|-$", "")
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "goal" }
  return "$Prefix-$($slug.Substring(0, [Math]::Min(48, $slug.Length)))"
}

function New-StableSlug {
  param([string]$Text, [string]$Fallback = "master-goal")
  $slug = (($Text ?? "").ToLowerInvariant() -replace "[^a-z0-9]+", "-" -replace "^-|-$", "")
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $Fallback }
  return $slug.Substring(0, [Math]::Min(72, $slug.Length))
}

function Get-HashText {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 16)
  } finally {
    $sha.Dispose()
  }
}

function ConvertTo-StringArray {
  param($Value)
  $items = @()
  if ($null -eq $Value) { return @() }
  foreach ($item in @($Value)) {
    if ($null -eq $item) { continue }
    if ($item -is [string]) {
      if (-not [string]::IsNullOrWhiteSpace($item)) { $items += $item }
    } elseif ($item.PSObject.Properties["constraints"]) {
      $items += ConvertTo-StringArray -Value $item.constraints
    } else {
      $text = [string]$item
      if (-not [string]::IsNullOrWhiteSpace($text)) { $items += $text }
    }
  }
  return @($items)
}

function Read-ConstraintsInput {
  param([string[]]$InlineConstraints, [string]$File, [string]$JsonText)
  $items = @($InlineConstraints | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "ConstraintsFile not found: $File" }
    $raw = Get-Content -Raw -LiteralPath $File
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      try {
        $items += ConvertTo-StringArray -Value ($raw | ConvertFrom-Json)
      } catch {
        $items += @($raw -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      }
    }
  }
  if ($JsonText) {
    $items += ConvertTo-StringArray -Value ($JsonText | ConvertFrom-Json)
  }
  return @($items)
}

function New-RuleBasedProposals {
  $base = "$ProjectId/$MasterGoalId"
  $dedupePrefix = New-StableSlug -Text $MasterGoalId -Fallback (New-StableSlug -Text $Title)
  $docsFile = "docs/dev/$($MasterGoalId.ToUpperInvariant() -replace '[^A-Z0-9]+', '_').md"
  @(
    [pscustomobject]@{
      proposal_id = "proposal-$(Get-HashText "$base/docs-record")"
      title = "Record master goal plan"
      body = "Create or update $docsFile with the reviewed plan for '$Title'."
      prompt_summary = "Document the reviewed master goal plan."
      dedupe_key = "$dedupePrefix-record"
      expected_files = @($docsFile, "docs/dev/PROGRESS.md")
      acceptance_criteria = @("Plan summary is documented.", "Safety constraints and stop conditions are recorded.")
      evidence_requirements = @("Changed files are docs-only.", "Validation command results are summarized.")
      required_capabilities = @("codex")
      risk = "low"
      task_type = "docs"
      depends_on = @()
      rationale = "Start with a docs-only record so the master goal is reviewable before execution."
      stop_condition = "Stop if the task would edit outside the expected docs files."
      status = "proposed"
      created_by = "rule-based-planner"
    },
    [pscustomobject]@{
      proposal_id = "proposal-$(Get-HashText "$base/runbook")"
      title = "Update operator runbook"
      body = "Update the relevant runbook with operator steps for '$Title'."
      prompt_summary = "Document operator workflow changes for the master goal."
      dedupe_key = "$dedupePrefix-runbook"
      expected_files = @("docs/orchestrator/SELF_BOOTSTRAP_SUPERVISOR.md")
      acceptance_criteria = @("Runbook includes preview-first workflow.", "No secrets or production deployment steps are introduced.")
      evidence_requirements = @("Docs validation passes.", "Updated section is linked from progress notes if meaningful.")
      required_capabilities = @("codex")
      risk = "low"
      task_type = "docs"
      depends_on = @()
      rationale = "Operator-facing changes need a safe documented path before repeat execution."
      stop_condition = "Stop if the change requires deployment, GitHub settings or secrets."
      status = "proposed"
      created_by = "rule-based-planner"
    },
    [pscustomobject]@{
      proposal_id = "proposal-$(Get-HashText "$base/smoke")"
      title = "Add local smoke coverage"
      body = "Add local smoke coverage for the first implementation slice of '$Title'."
      prompt_summary = "Add safe local smoke coverage."
      dedupe_key = "$dedupePrefix-smoke"
      expected_files = @("scripts/powershell/smoke-$($MasterGoalId.ToLowerInvariant() -replace '[^a-z0-9]+', '-').ps1")
      acceptance_criteria = @("Smoke uses a local test server or fixture.", "Smoke does not require real cloud credentials.", "Smoke does not run real Codex by default.")
      evidence_requirements = @("Smoke output shows token_printed=false where applicable.", "validate-powershell.ps1 passes.")
      required_capabilities = @("codex")
      risk = "medium"
      task_type = "local-smoke"
      depends_on = @()
      rationale = "A local smoke is the first reliability gate before cloud mutation or worker execution."
      stop_condition = "Stop before any real cloud mutation."
      status = "proposed"
      created_by = "rule-based-planner"
    }
  )
}

function Get-StrictJsonText {
  param($Response)
  if ($null -eq $Response) { throw "Hermes response was empty." }
  if ($Response.output_text) { return [string]$Response.output_text }
  if ($Response.text) { return [string]$Response.text }
  if ($Response.content) { return [string]$Response.content }
  $parts = @()
  foreach ($item in @($Response.output)) {
    foreach ($content in @($item.content)) {
      if ($content.text) { $parts += [string]$content.text }
    }
  }
  if ($parts.Count -gt 0) { return ($parts -join "`n") }
  return ($Response | ConvertTo-Json -Depth 20)
}

function ConvertFrom-StrictProposalJson {
  param([string]$Text)
  $trimmed = $Text.Trim()
  if ($trimmed -match '```(?:json)?\s*([\s\S]*?)\s*```') { $trimmed = $Matches[1].Trim() }
  $parsed = $trimmed | ConvertFrom-Json
  $raw = if ($parsed.proposals) { @($parsed.proposals) } elseif ($parsed.title) { @($parsed) } else { @() }
  if (@($raw).Count -eq 0) { throw "Hermes planner returned no proposals." }
  $raw | ForEach-Object {
    foreach ($field in @("title", "body", "prompt_summary", "task_type", "risk", "dedupe_key", "rationale", "stop_condition")) {
      if ([string]::IsNullOrWhiteSpace([string]$_.($field))) { throw "Planner proposal missing $field." }
    }
    foreach ($field in @("required_capabilities", "expected_files", "acceptance_criteria", "evidence_requirements", "depends_on")) {
      if ($null -eq $_.($field)) { throw "Planner proposal missing $field." }
    }
    [pscustomobject]@{
      proposal_id = if ($_.proposal_id) { [string]$_.proposal_id } else { "proposal-$(Get-HashText "$ProjectId/$MasterGoalId/$($_.dedupe_key)")" }
      title = [string]$_.title
      body = [string]$_.body
      prompt_summary = [string]$_.prompt_summary
      task_type = [string]$_.task_type
      risk = [string]$_.risk
      required_capabilities = @($_.required_capabilities)
      expected_files = @($_.expected_files)
      acceptance_criteria = @($_.acceptance_criteria)
      evidence_requirements = @($_.evidence_requirements)
      dedupe_key = [string]$_.dedupe_key
      depends_on = @($_.depends_on)
      rationale = [string]$_.rationale
      stop_condition = [string]$_.stop_condition
      status = "proposed"
      created_by = "hermes-planner"
    }
  }
}

function Normalize-HermesProposalTaskTypes {
  param([array]$Proposals)
  foreach ($proposal in @($Proposals)) {
    $raw = ([string]$proposal.task_type).Trim()
    $normalized = $raw.ToLowerInvariant()
    $files = @($proposal.expected_files | ForEach-Object { ([string]$_).Replace("\", "/") })
    $newType = $normalized
    switch ($normalized) {
      "smoke" { $newType = "local-smoke" }
      "doc" { $newType = "docs" }
      "documentation" { $newType = "docs" }
      "test" {
        $safeSmokeFiles = @($files | Where-Object { $_ -like "scripts/powershell/smoke-*.ps1" })
        if ($files.Count -gt 0 -and $safeSmokeFiles.Count -eq $files.Count) { $newType = "local-smoke" }
      }
      default { $newType = $normalized }
    }
    if ($newType -ne $raw) {
      $proposal | Add-Member -NotePropertyName original_task_type -NotePropertyValue $raw -Force
      $proposal.task_type = $newType
    }
    if ($normalized -in @("deploy", "production", "secret", "secrets", "github-settings", "branch-protection", "server-config", "server-root-config")) {
      $proposal | Add-Member -NotePropertyName blocked_task_type -NotePropertyValue $normalized -Force
    }
  }
  return $Proposals
}

function Normalize-HermesProposalCapabilities {
  param([array]$Proposals)
  foreach ($proposal in @($Proposals)) {
    $original = @($proposal.required_capabilities | ForEach-Object {
      $capability = ([string]$_).Trim()
      if (-not [string]::IsNullOrWhiteSpace($capability)) { $capability.ToLowerInvariant() }
    } | Where-Object { $_ } | Select-Object -Unique)
    $normalized = @($original)
    $reason = $null
    $taskType = ([string]$proposal.task_type).Trim().ToLowerInvariant()
    $files = @($proposal.expected_files | ForEach-Object { ([string]$_).Replace("\", "/") })
    $docsOnly = $files.Count -gt 0 -and @($files | Where-Object { $_ -like "docs/*" }).Count -eq $files.Count
    $safeSmokeOnly = $files.Count -gt 0 -and @($files | Where-Object { $_ -like "scripts/powershell/smoke-*.ps1" }).Count -eq $files.Count

    if ($taskType -eq "docs" -and $docsOnly) {
      $normalized = @($normalized | Where-Object { $_ -ne "docs" -and $_ -ne "documentation" })
      foreach ($capability in @("codex", "git", "gh")) {
        if ($normalized -notcontains $capability) { $normalized += $capability }
      }
      $reason = "docs_expected_files_use_codex_git_gh"
    } elseif ($taskType -eq "local-smoke" -and $safeSmokeOnly) {
      $normalized = @($normalized | Where-Object { $_ -ne "smoke" -and $_ -ne "local-smoke" })
      foreach ($capability in @("codex", "powershell", "windows")) {
        if ($normalized -notcontains $capability) { $normalized += $capability }
      }
      $reason = "safe_local_smoke_expected_files_use_codex_powershell_windows"
    }

    $proposal | Add-Member -NotePropertyName original_required_capabilities -NotePropertyValue @($original) -Force
    $proposal | Add-Member -NotePropertyName normalized_required_capabilities -NotePropertyValue @($normalized | Select-Object -Unique) -Force
    if ($reason) { $proposal | Add-Member -NotePropertyName capability_normalization_reason -NotePropertyValue $reason -Force }
  }
  return $Proposals
}

function ConvertTo-TaskSummary {
  param($Task)
  $metadata = $Task.planner_metadata
  $result = $Task.result
  [pscustomobject]@{
    task_id = $Task.task_id
    title = $Task.title
    status = $Task.status
    risk = if ($metadata) { $metadata.risk } else { $null }
    task_type = if ($metadata) { $metadata.task_type } else { $Task.task_type }
    dedupe_key = if ($metadata) { $metadata.dedupe_key } else { $Task.dedupe_key }
    assigned_worker_id = $Task.assigned_worker_id
    pr_url = if ($result) { $result.pr_url } else { $null }
    evidence_status = if ($result -and $result.evidence_summary) { $result.evidence_summary.recovery_status } else { $null }
    changed_files = if ($metadata) { @($metadata.expected_files) } else { @() }
  }
}

function ConvertTo-WorkerSummary {
  param($Worker)
  [pscustomobject]@{
    worker_id = $Worker.worker_id
    status = $Worker.status
    hostname = $Worker.hostname
    capabilities = @($Worker.capabilities)
    current_task_id = $Worker.current_task_id
    last_heartbeat_at = $Worker.last_heartbeat_at
  }
}

function New-CompactPlannerState {
  param($Health, $Project, $Control, [array]$Tasks, [array]$Workers)
  $taskList = @($Tasks)
  $active = @($taskList | Where-Object { $_.status -in @("queued", "claimed", "running") })
  $recent = @($taskList | Select-Object -First 10 | ForEach-Object { ConvertTo-TaskSummary -Task $_ })
  $blocked = @($taskList | Where-Object { $_.status -eq "blocked" } | Select-Object -First 10 | ForEach-Object { ConvertTo-TaskSummary -Task $_ })
  $recovered = @($taskList | Where-Object { $_.status -eq "recovered" -or ($_.result -and $_.result.evidence_summary -and $_.result.evidence_summary.recovered -eq $true) } | Select-Object -First 10 | ForEach-Object { ConvertTo-TaskSummary -Task $_ })
  $statusSummary = @{}
  foreach ($group in @($taskList | Group-Object -Property status)) { $statusSummary[$group.Name] = $group.Count }
  [pscustomobject]@{
    schema = "skybridge.planner_compact_state.v1"
    health = [pscustomobject]@{
      ok = $Health.ok
      service = $Health.service
      version = $Health.version
    }
    project = [pscustomobject]@{
      project_id = $Project.project_id
      name = $Project.name
      status = $Project.status
    }
    control = [pscustomobject]@{
      state = $Control.state
      max_tasks = $Control.max_tasks
      updated_at = $Control.updated_at
    }
    active_task_count = $active.Count
    queued_task_count = @($active | Where-Object { $_.status -eq "queued" }).Count
    running_task_count = @($active | Where-Object { $_.status -in @("claimed", "running") }).Count
    task_status_summary = $statusSummary
    recent_tasks = @($recent)
    blocked_tasks = @($blocked)
    recovered_tasks = @($recovered)
    workers = @($Workers | Select-Object -First 10 | ForEach-Object { ConvertTo-WorkerSummary -Worker $_ })
    recent_pr_evidence = @($recent | Where-Object { $_.pr_url } | Select-Object -First 10)
    raw_task_events_included = $false
    raw_prompts_included = $false
    raw_logs_included = $false
    secrets_included = $false
  }
}

function Invoke-HermesProposalPlanner {
  param($State)
  $loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
  if (Test-Path -LiteralPath $loader -PathType Leaf) { . $loader }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)) { throw "HERMES_API_BASE is missing." }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) { throw "HERMES_API_KEY is missing." }
  $stateJson = $State | ConvertTo-Json -Depth 16
  $constraintsText = (@($Constraints) + @(
    "Return strict JSON only.",
    "Do not execute commands or modify files.",
    "Use only task_type values docs or local-smoke.",
    "Executable proposals must include execution capabilities in required_capabilities, not task-type labels.",
    "For docs proposals under docs/, use required_capabilities such as codex, git and gh; do not use docs as a required worker capability.",
    "For local-smoke proposals under scripts/powershell/smoke-*.ps1, use codex, powershell and windows.",
    "Expected files must stay under docs/ or scripts/powershell/smoke-*.ps1.",
    "No production deployment, secrets, GitHub settings, branch protection or server root config."
  )) -join "`n- "
  $prompt = @"
You are Hermes acting as an advisory PlannerAdapter for SkyBridge Agent Hub.

Return JSON with a top-level proposals array. Each proposal must include:
title, body, prompt_summary, task_type, risk, required_capabilities, expected_files,
acceptance_criteria, evidence_requirements, dedupe_key, depends_on, rationale, stop_condition.

Master goal:
$Title

Description:
$Description

Constraints:
- $constraintsText

Current SkyBridge state JSON:
$stateJson
"@
  $body = @{
    model = if ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
    input = $prompt
    response_format = @{ type = "json_object" }
  }
  Invoke-RestMethod -Method POST -Uri "$($env:HERMES_API_BASE.TrimEnd('/'))/v1/responses" -Headers @{ Authorization = "Bearer $env:HERMES_API_KEY"; "Content-Type" = "application/json" } -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSeconds
}

function Test-ProposalPolicy {
  param([array]$Proposals, [array]$ExistingProposals, [string]$Mode)
  $existingKeys = @($ExistingProposals | ForEach-Object { [string]$_.dedupe_key })
  $seen = @{}
  foreach ($proposal in @($Proposals)) {
    $reasons = New-Object System.Collections.Generic.List[string]
    $decision = "accepted_for_preview"
    $risk = [string]$proposal.risk
    $taskType = [string]$proposal.task_type
    $files = @($proposal.expected_files | ForEach-Object { ([string]$_).Replace("\", "/") })
    $capsSource = if ($proposal.PSObject.Properties["normalized_required_capabilities"]) { $proposal.normalized_required_capabilities } else { $proposal.required_capabilities }
    $caps = @($capsSource | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $dedupe = [string]$proposal.dedupe_key

    if ([string]::IsNullOrWhiteSpace($dedupe) -or $seen.ContainsKey($dedupe) -or ($existingKeys -contains $dedupe)) {
      $decision = "rejected_duplicate"; $reasons.Add("dedupe_key is missing or duplicated") | Out-Null
    }
    $seen[$dedupe] = $true
    if ($taskType -in @("deploy", "production", "secret", "secrets", "github-settings", "branch-protection", "server-config", "server-root-config") -or $proposal.blocked_task_type) {
      $decision = "ask_human"; $reasons.Add("task_type is blocked for Hermes-assisted automation") | Out-Null
    } elseif ($taskType -notin @("docs", "local-smoke")) {
      $decision = "ask_human"; $reasons.Add("task_type must be docs or local-smoke") | Out-Null
    }
    if ($risk -ne "low") {
      $decision = "rejected_high_risk"; $reasons.Add("risk must be low") | Out-Null
    }
    if ($caps -notcontains "codex") {
      $decision = "ask_human"; $reasons.Add("required_capabilities must include codex") | Out-Null
    }
    if (@($proposal.acceptance_criteria).Count -eq 0 -or @($proposal.evidence_requirements).Count -eq 0) {
      $decision = "ask_human"; $reasons.Add("acceptance_criteria and evidence_requirements are required") | Out-Null
    }
    $blockedText = (@($proposal.title, $proposal.body, $proposal.prompt_summary, $proposal.rationale, @($proposal.expected_files)) -join " ")
    if ($blockedText -match "(?i)(production deploy|docker daemon|branch protection|github settings|/opt/skybridge-agent-hub|commit \.env|token file|private key)") {
      $decision = "ask_human"; $reasons.Add("proposal mentions a blocked high-risk surface") | Out-Null
    }
    foreach ($file in $files) {
      $allowed = $file -like "docs/*" -or $file -like "scripts/powershell/smoke-*.ps1"
      if (-not $allowed -or $file -like ".agent/*" -or $file -like ".data/*" -or $file -like ".env*" -or $file -like "deploy/*") {
        $decision = "rejected_expected_files"; $reasons.Add("expected file is outside allowed docs/local-smoke paths: $file") | Out-Null
      }
    }
    if ($decision -eq "accepted_for_preview" -and $Mode -eq "execution") { $decision = "accepted_for_execution" }
    $proposal | Add-Member -NotePropertyName policy_decision -NotePropertyValue $decision -Force
    $proposal | Add-Member -NotePropertyName policy_reasons -NotePropertyValue @($reasons.ToArray()) -Force
    if (-not $proposal.PSObject.Properties["review_status"]) {
      $proposal | Add-Member -NotePropertyName review_status -NotePropertyValue "proposed" -Force
    }
    if (-not $proposal.PSObject.Properties["dependencies"]) {
      $proposal | Add-Member -NotePropertyName dependencies -NotePropertyValue @($proposal.depends_on) -Force
    }
  }
  return $Proposals
}

function Write-PlanResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 60 -Compress; return }
  "Mode:         $($Result.mode)"
  "Planner:      $($Result.planner_mode)"
  "Runtime:      $($Result.planner_adapter.runtime_mode)"
  "Model:        $($Result.planner_adapter.model)"
  "MasterGoal:   $($Result.master_goal.master_goal_id)"
  "Project:      $($Result.project_id)"
  "Proposals:    $(@($Result.proposals).Count)"
  foreach ($proposal in @($Result.proposals)) {
    "  $($proposal.proposal_id) [$($proposal.risk)] $($proposal.policy_decision) $($proposal.title)"
    "    files: $(@($proposal.expected_files) -join ', ')"
  }
  "TokenPrinted: false"
}

if ([string]::IsNullOrWhiteSpace($Title)) { throw "skybridge-plan requires -Title." }
if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-Slug -Prefix "master-goal" -Text $Title }
if ($PlannerMode -eq "hermes-apply" -and -not $Apply) { throw "hermes-apply requires -Apply." }
if ($PlannerMode -eq "hermes-preview" -and $Apply) { throw "hermes-preview is preview-only; use hermes-apply for persistence." }
$effectiveConstraints = @(Read-ConstraintsInput -InlineConstraints $Constraints -File $ConstraintsFile -JsonText $ConstraintsJson)
$Constraints = $effectiveConstraints

$script:Config = New-PlanApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$effectiveDryRun = $DryRun -or -not $Apply
$health = Invoke-PlanApi -Method GET -Path "/v1/health"
$project = Invoke-PlanApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
$control = Invoke-PlanApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/control"
$tasks = Invoke-PlanApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))"
$workers = Invoke-PlanApi -Method GET -Path "/v1/workers"
$existingProposalsPayload = $null
try { $existingProposalsPayload = Invoke-PlanApi -Method GET -Path "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))" } catch {}

$state = if ($StateMode -eq "full") {
  [pscustomobject]@{
    schema = "skybridge.planner_full_state.v1"
    health = $health
    project = $project.project
    control = $control.control_state
    recent_tasks = @($tasks.tasks | Select-Object -First 10)
    workers = @($workers.workers | Select-Object -First 10)
  }
} else {
  New-CompactPlannerState -Health $health -Project $project.project -Control $control.control_state -Tasks @($tasks.tasks) -Workers @($workers.workers)
}
$stateHash = Get-HashText (($state | ConvertTo-Json -Depth 20 -Compress))
$now = (Get-Date).ToUniversalTime().ToString("o")
$masterGoal = [pscustomobject]@{
  master_goal_id = $MasterGoalId
  project_id = $ProjectId
  title = $Title
  description = $Description
  source = "manual"
  priority = "normal"
  constraints = @($effectiveConstraints)
  acceptance_criteria = @($AcceptanceCriteria)
  stop_conditions = @($StopConditions)
}

$provider = if ($PlannerMode -eq "rule-based") { "rule-based-planner" } else { "hermes" }
$runtimeMode = if ($FixtureFile) { "fixture" } elseif ($PlannerMode -eq "rule-based") { "deterministic" } else { "real-api" }
$model = if ($PlannerMode -eq "rule-based") { "deterministic-rules" } elseif ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
$plannerAdapter = [pscustomobject]@{
  provider = $provider
  model = $model
  runtime_mode = $runtimeMode
  planner_mode = $PlannerMode
  tool_execution_mode = "disabled"
  prompt_version = "hermes-assisted-proposal-v1"
  input_state_hash = $stateHash
  session_id = "planning-session-$(Get-HashText "$MasterGoalId/$now")"
  raw_response_included = $false
  secrets_included = $false
}

if ($PlannerMode -eq "rule-based") {
  $proposals = @(New-RuleBasedProposals)
} elseif ($FixtureFile) {
  $proposals = @(ConvertFrom-StrictProposalJson -Text (Get-Content -Raw -LiteralPath $FixtureFile))
} else {
  $response = Invoke-HermesProposalPlanner -State $state
  $proposals = @(ConvertFrom-StrictProposalJson -Text (Get-StrictJsonText -Response $response))
}

$proposals = @(Normalize-HermesProposalTaskTypes -Proposals $proposals)
$proposals = @(Normalize-HermesProposalCapabilities -Proposals $proposals)
$policyMode = if ($PlannerMode -eq "hermes-apply") { "execution" } else { "preview" }
$proposals = @(Test-ProposalPolicy -Proposals $proposals -ExistingProposals @($existingProposalsPayload.proposals) -Mode $policyMode)
$persistableProposals = if ($PlannerMode -eq "hermes-apply") {
  @($proposals | Where-Object { $_.policy_decision -eq "accepted_for_execution" })
} elseif ($PlannerMode -eq "rule-based") {
  @($proposals | Where-Object { $_.policy_decision -eq "accepted_for_preview" -or $_.policy_decision -eq "accepted_for_execution" })
} else {
  @()
}

$session = [pscustomobject]@{
  planning_session_id = $plannerAdapter.session_id
  master_goal_id = $MasterGoalId
  project_id = $ProjectId
  planner_adapter = $plannerAdapter
  proposals = [object[]]@($proposals)
}

$masterGoalAction = "would_create"
$sessionAction = "would_create"
if (-not $effectiveDryRun) {
  try {
    Invoke-PlanApi -Method GET -Path "/v1/master-goals/$([uri]::EscapeDataString($MasterGoalId))" | Out-Null
    $masterGoalAction = "existing"
  } catch {
    Invoke-PlanApi -Method POST -Path "/v1/master-goals" -Body $masterGoal | Out-Null
    $masterGoalAction = "created"
  }
  if (@($persistableProposals).Count -eq 0) { throw "No proposals passed SkyBridge validation for persistence." }
  $sessionForApi = [pscustomobject]@{
    planning_session_id = $plannerAdapter.session_id
    master_goal_id = $MasterGoalId
    project_id = $ProjectId
    planner_adapter = $plannerAdapter
    proposals = [object[]]@($persistableProposals)
  }
  $applied = Invoke-PlanApi -Method POST -Path "/v1/planning-sessions" -Body $sessionForApi
  $sessionAction = "created"
  $persistableProposals = @($applied.proposals)
}

Write-PlanResult ([pscustomobject]@{
  ok = $true
  mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
  planner_mode = $PlannerMode
  project_id = $ProjectId
  token_printed = $false
  master_goal = $masterGoal
  master_goal_action = $masterGoalAction
  planning_session = $session
  planning_session_action = $sessionAction
  planner_adapter = $plannerAdapter
  project_state = $state
  proposals = $proposals
  persistable_proposals = $persistableProposals
})
