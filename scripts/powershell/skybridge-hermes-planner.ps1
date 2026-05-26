[CmdletBinding()]
param(
  [string]$MasterGoalFile = ".\goals\master\self-bootstrap-smoke.md",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId = "self-bootstrap-smoke",
  [string]$ProjectStateJson,
  [string]$CompactStateFile,
  [string]$FixtureFile,
  [switch]$CreateTask,
  [switch]$DryRun,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Get-SafeFileText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  return Get-Content -Raw -LiteralPath $Path
}

function New-HermesHeaders {
  param([Parameter(Mandatory = $true)][string]$ApiKey)
  return @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }
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

function ConvertFrom-StrictPlannerJson {
  param([Parameter(Mandatory = $true)][string]$Text)
  $trimmed = $Text.Trim()
  if ($trimmed -match '```(?:json)?\s*([\s\S]*?)\s*```') { $trimmed = $Matches[1].Trim() }
  $parsed = $trimmed | ConvertFrom-Json
  Test-PlannerDecisionSchema -Decision $parsed
  return $parsed
}

function Test-PlannerDecisionSchema {
  param($Decision)
  $allowed = @("continue", "repair", "wait", "stop", "blocked")
  if ($allowed -notcontains [string]$Decision.decision) { throw "Invalid planner decision: $($Decision.decision)" }
  if ([string]::IsNullOrWhiteSpace($Decision.reason)) { throw "Planner decision missing reason." }
  if ($Decision.decision -in @("continue", "repair")) {
    if ($null -eq $Decision.task) { throw "Planner decision $($Decision.decision) requires task." }
    foreach ($field in @("title", "task_type", "risk", "prompt")) {
      if ([string]::IsNullOrWhiteSpace($Decision.task.$field)) { throw "Planner task missing $field." }
    }
    if (@("low", "medium", "high") -notcontains [string]$Decision.task.risk) { throw "Planner task has invalid risk." }
    foreach ($field in @("allowed_paths", "blocked_paths", "validation", "expected_files", "depends_on")) {
      if ($null -eq $Decision.task.$field -or $Decision.task.$field.GetType().Name -notmatch "Object\[\]|ArrayList") {
        throw "Planner task $field must be an array."
      }
    }
    foreach ($field in @("dedupe_key", "advances_acceptance", "merge_strategy")) {
      if ([string]::IsNullOrWhiteSpace($Decision.task.$field)) { throw "Planner task missing $field." }
    }
    if (@("auto_pr_auto_merge", "auto_pr_manual_merge", "human_review") -notcontains [string]$Decision.task.merge_strategy) {
      throw "Planner task has invalid merge_strategy."
    }
  }
  if ($null -eq $Decision.stop_criteria_status) { $Decision | Add-Member -NotePropertyName stop_criteria_status -NotePropertyValue @() -Force }
}

function New-DryRunPlannerDecision {
  param([int]$Round = 1)
  return [pscustomobject]@{
    decision = "continue"
    reason = "Dry-run fixture selects a docs-only task for self-bootstrap round $Round."
    task = [pscustomobject]@{
      title = "Document Hermes self-bootstrap round $Round"
      task_type = "docs"
      risk = "low"
      prompt = "Update docs only with a concise note for Hermes self-bootstrap round $Round. Do not edit code, env files, production config or GitHub settings."
      allowed_paths = @("docs/orchestrator/", "docs/dev/PROGRESS.md", "goals/master/self-bootstrap-smoke.md")
      blocked_paths = @(".env", "config/*.secret.ps1", ".agent/", ".data/", "deploy/production", "/opt/")
      validation = @("corepack pnpm check")
      dedupe_key = "docs/hermes-self-bootstrap-round-$Round"
      expected_files = @("docs/dev/PROGRESS.md")
      depends_on = @()
      advances_acceptance = "Documents self-bootstrap proof round $Round."
      merge_strategy = "auto_pr_auto_merge"
    }
    stop_criteria_status = @("round_$Round planned", "three_round_docs_only_proof in_progress")
  }
}

function Invoke-HermesPlanner {
  param([string]$Prompt)
  $loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
  if (Test-Path -LiteralPath $loader -PathType Leaf) { . $loader }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)) { throw "HERMES_API_BASE is missing." }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) { throw "HERMES_API_KEY is missing." }
  $body = @{
    model = if ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
    input = $Prompt
    response_format = @{ type = "json_object" }
  }
  return Invoke-RestMethod -Method POST -Uri "$($env:HERMES_API_BASE.TrimEnd('/'))/v1/responses" -Headers (New-HermesHeaders -ApiKey $env:HERMES_API_KEY) -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 20) -TimeoutSec 120
}

function New-SkyBridgeTaskFromPlannerDecision {
  param($Decision)
  if ($Decision.decision -notin @("continue", "repair")) { return $null }
  $project = $null
  try { $project = Invoke-SkyBridgeApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase } catch {}
  if (-not $project) {
    Invoke-SkyBridgeApi -Method POST -Path "/v1/projects" -ApiBase $ApiBase -Body @{
      project_id = $ProjectId
      name = "SkyBridge Agent Hub"
      repo = "JerrySkywalker/skybridge-agent-hub"
      description = "Hermes self-bootstrap pilot project."
    } | Out-Null
  }
  $goal = $null
  try { $goal = Invoke-SkyBridgeApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($GoalId))" -ApiBase $ApiBase } catch {}
  if (-not $goal) {
    Invoke-SkyBridgeApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -ApiBase $ApiBase -Body @{
      goal_id = $GoalId
      title = "Hermes planned self-bootstrap smoke"
      summary = "Complete three docs-only rounds planned by optional Hermes PlannerAdapter."
      status = "active"
    } | Out-Null
  }
  $slug = (([string]$Decision.task.title).ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
  if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).Trim("-") }
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "hermes-task" }
  $taskId = "hermes-$slug-$((Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))"
  $metadata = @{
    adapter = "hermes-planner"
    decision = [string]$Decision.decision
    reason = [string]$Decision.reason
    task_type = [string]$Decision.task.task_type
    allowed_paths = @($Decision.task.allowed_paths)
    blocked_paths = @($Decision.task.blocked_paths)
    validation = @($Decision.task.validation)
    dedupe_key = [string]$Decision.task.dedupe_key
    expected_files = @($Decision.task.expected_files)
    depends_on = @($Decision.task.depends_on)
    advances_acceptance = [string]$Decision.task.advances_acceptance
    merge_strategy = [string]$Decision.task.merge_strategy
    stop_criteria_status = @($Decision.stop_criteria_status)
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    raw_response_included = $false
    secrets_included = $false
  }
  return Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks" -ApiBase $ApiBase -Body @{
    task_id = $taskId
    project_id = $ProjectId
    goal_id = $GoalId
    title = [string]$Decision.task.title
    body = [string]$Decision.task.prompt
    prompt_summary = ([string]$Decision.task.prompt).Substring(0, [Math]::Min(240, ([string]$Decision.task.prompt).Length))
    risk = [string]$Decision.task.risk
    source = "hermes-planner"
    task_type = [string]$Decision.task.task_type
    planner_metadata = $metadata
    allowed_paths = @($Decision.task.allowed_paths)
    blocked_paths = @($Decision.task.blocked_paths)
    validation = @($Decision.task.validation)
    required_capabilities = @("codex-exec", "docs")
  }
}

$masterGoal = Get-SafeFileText -Path $MasterGoalFile
$promptTemplate = Get-SafeFileText -Path (Join-Path $PSScriptRoot "..\..\docs\hermes\prompts\self-bootstrap-planner.md")
$statePath = if ($CompactStateFile) { $CompactStateFile } else { $ProjectStateJson }
$state = if ($statePath -and (Test-Path -LiteralPath $statePath -PathType Leaf)) { Get-Content -Raw -LiteralPath $statePath } else { "{}" }
$prompt = @"
$promptTemplate

Master goal:
$masterGoal

Current SkyBridge state JSON:
$state
"@

if ($DryRun) {
  if ($FixtureFile) {
    $decision = ConvertFrom-StrictPlannerJson -Text (Get-Content -Raw -LiteralPath $FixtureFile)
  } else {
    $decision = New-DryRunPlannerDecision
    Test-PlannerDecisionSchema -Decision $decision
  }
} else {
  $decision = $null
  $lastText = $null
  for ($attempt = 0; $attempt -lt 3 -and $null -eq $decision; $attempt += 1) {
    $response = Invoke-HermesPlanner -Prompt $(if ($attempt -eq 0) { $prompt } else { "$prompt`nRepair this invalid JSON response and return only valid strict JSON:`n$lastText" })
    $lastText = Get-StrictJsonText -Response $response
    try { $decision = ConvertFrom-StrictPlannerJson -Text $lastText } catch { if ($attempt -ge 2) { throw } }
  }
}

$taskResponse = $null
if ($CreateTask) { $taskResponse = New-SkyBridgeTaskFromPlannerDecision -Decision $decision }

$result = [pscustomobject]@{
  ok = $true
  dry_run = [bool]$DryRun
  hermes_api_key_value_included = $false
  decision = $decision
  task = $taskResponse.task
}

if ($Json) { $result | ConvertTo-Json -Depth 30 } else { $result | Format-List }
