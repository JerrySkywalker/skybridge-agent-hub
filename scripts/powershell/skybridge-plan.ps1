[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [string]$Title,
  [string]$Description,
  [string[]]$Constraints = @(),
  [string[]]$AcceptanceCriteria = @("Task proposals are reviewed before executable tasks are created."),
  [string[]]$StopConditions = @("Stop before any high-risk or production deployment work."),
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [ValidateSet("rule-based", "hermes")]
  [string]$PlannerMode = "rule-based",
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
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 20
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

function New-RuleBasedProposals {
  param($State)
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
      status = "proposed"
      created_by = "rule-based-planner"
    },
    [pscustomobject]@{
      proposal_id = "proposal-$(Get-HashText "$base/runbook")"
      title = "Update operator runbook"
      body = "Update the relevant runbook with operator steps for '$Title'."
      prompt_summary = "Document operator workflow changes for the master goal."
      dedupe_key = "$dedupePrefix-runbook"
      expected_files = @("docs/orchestrator/WORKER_PROFILE_RUNBOOK.md")
      acceptance_criteria = @("Runbook includes preview-first workflow.", "No secrets or production deployment steps are introduced.")
      evidence_requirements = @("Docs validation passes.", "Updated section is linked from progress notes if meaningful.")
      required_capabilities = @("codex")
      risk = "low"
      task_type = "docs"
      depends_on = @()
      rationale = "Operator-facing changes need a safe documented path before repeat execution."
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
      task_type = "test"
      depends_on = @()
      rationale = "A local smoke is the first reliability gate before cloud mutation or worker execution."
      status = "proposed"
      created_by = "rule-based-planner"
    }
  )
}

function Write-PlanResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 50 -Compress; return }
  "Mode:         $($Result.mode)"
  "Planner:      $($Result.planner_mode)"
  "MasterGoal:   $($Result.master_goal.master_goal_id)"
  "Project:      $($Result.project_id)"
  "Proposals:    $(@($Result.proposals).Count)"
  foreach ($proposal in @($Result.proposals)) {
    "  $($proposal.proposal_id) [$($proposal.risk)] $($proposal.title)"
    "    files: $(@($proposal.expected_files) -join ', ')"
  }
  "TokenPrinted: false"
}

if ([string]::IsNullOrWhiteSpace($Title)) { throw "skybridge-plan requires -Title." }
if ([string]::IsNullOrWhiteSpace($MasterGoalId)) { $MasterGoalId = New-Slug -Prefix "master-goal" -Text $Title }
if ($PlannerMode -eq "hermes") { throw "Hermes planner mode is a disabled adapter seam for now. Use -PlannerMode rule-based." }

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

$state = [pscustomobject]@{
  health = $health
  project = $project.project
  control = $control.control_state
  recent_tasks = @($tasks.tasks | Select-Object -First 10)
  workers = @($workers.workers | Select-Object -First 10)
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
  constraints = @($Constraints)
  acceptance_criteria = @($AcceptanceCriteria)
  stop_conditions = @($StopConditions)
}
$plannerAdapter = [pscustomobject]@{
  provider = "rule-based-planner"
  model = "deterministic-rules"
  planner_mode = $PlannerMode
  prompt_version = "master-goal-planner-v1"
  input_state_hash = $stateHash
  raw_response_included = $false
  secrets_included = $false
}
$proposals = @(New-RuleBasedProposals -State $state)
$session = [pscustomobject]@{
  planning_session_id = "planning-session-$(Get-HashText "$MasterGoalId/$now")"
  master_goal_id = $MasterGoalId
  project_id = $ProjectId
  planner_adapter = $plannerAdapter
  proposals = $proposals
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
  $applied = Invoke-PlanApi -Method POST -Path "/v1/planning-sessions" -Body $session
  $sessionAction = "created"
  $proposals = @($applied.proposals)
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
})
