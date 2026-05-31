[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("init", "validate-pack", "import", "list", "show", "steps", "status", "start", "pause", "hold", "resume", "advance-preview", "advance", "gate-preview", "hermes-gate-preview", "advance-with-gate", "attach-gate-evidence", "complete-step", "fail-step", "attach-evidence", "export-report")]
  [string]$Command = "status",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId,
  [string]$GoalPackDir,
  [string]$ManifestFile,
  [string]$StepId,
  [string]$GoalId,
  [string]$TokenFile,
  [string]$TokenEnvVar,
  [switch]$UseHermesGate,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [string]$HermesGateFixtureFile,
  [string]$PromptVersion = "campaign-gate-v1",
  [string]$HumanApprovalReason,
  [string]$SaveGateInput,
  [string]$SaveGateOutput,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason,
  [string]$EvidenceSummary,
  [string[]]$LinkedTaskIds = @(),
  [string[]]$LinkedPrUrls = @(),
  [switch]$HumanApproved
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-CampaignApiConfig {
  $authMode = "none"
  if ($TokenEnvVar -or $TokenFile) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Invoke-CampaignApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 30
}

function Get-JsonHash {
  param([Parameter(Mandatory = $true)][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function ConvertTo-JsonObject {
  param($Value)
  return ($Value | ConvertTo-Json -Depth 80 -Compress)
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Get-GoalPackManifestPath {
  if ($ManifestFile) { return (Resolve-Path -LiteralPath $ManifestFile -ErrorAction Stop).Path }
  if (-not $GoalPackDir) { throw "$Command requires -GoalPackDir or -ManifestFile." }
  $candidate = Join-Path $GoalPackDir "campaign.skybridge.json"
  return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
}

function Get-MarkdownMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)
  $raw = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($raw, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { throw "Goal markdown missing fenced JSON metadata: $Path" }
  $metadata = $match.Groups[1].Value | ConvertFrom-Json
  $body = [regex]::Replace($raw, '(?ms)```json\s*\{.*?\}\s*```', "", 1).Trim()
  [pscustomobject]@{ metadata = $metadata; body = $body; raw = $raw }
}

function Test-TokenLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match "(?i)(sk-[A-Za-z0-9_-]{20,}|skybridge[_-]?worker[_-]?token\s*[:=]|hermes[_-]?api[_-]?key\s*[:=]|-----BEGIN (RSA |OPENSSH |PRIVATE )?PRIVATE KEY-----)"
}

function Test-SensitiveAbsolutePath {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match "(?i)([A-Z]:\\Users\\[^\\]+\\\.skybridge|/home/[^/]+/\.skybridge|/root/|/opt/.+\.env|\\\.ssh\\|/\.ssh/)"
}

function Invoke-CampaignJsonScript {
  param([string[]]$Arguments)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    $message = ($output | ForEach-Object { [string]$_ }) -join "`n"
    throw "Command failed: pwsh $($Arguments -join ' ')`n$message"
  }
  return ($output | ConvertFrom-Json)
}

function Get-GitMetadata {
  $branch = $null
  $commit = $null
  $dirty = $null
  try { $branch = (git branch --show-current).Trim() } catch {}
  try { $commit = (git rev-parse HEAD).Trim() } catch {}
  try { $dirty = -not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim()) } catch {}
  [pscustomobject]@{
    branch = $branch
    commit = $commit
    dirty = $dirty
  }
}

function Get-StrictHermesText {
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
  return ($Response | ConvertTo-Json -Depth 30)
}

function ConvertFrom-StrictGateJson {
  param([Parameter(Mandatory = $true)][string]$Text)
  $trimmed = $Text.Trim()
  if ($trimmed -match '```') { throw "Hermes gate response must be strict JSON without Markdown fences." }
  $parsed = $trimmed | ConvertFrom-Json
  Test-CampaignGateSchema -Gate $parsed
  return $parsed
}

function Test-CampaignGateSchema {
  param($Gate)
  $allowed = @("advance", "hold", "retry", "ask_human", "abort")
  if ($Gate.schema -ne "skybridge.campaign_gate.v1") { throw "Invalid gate schema: $($Gate.schema)" }
  if ($allowed -notcontains [string]$Gate.decision) { throw "Invalid gate decision: $($Gate.decision)" }
  $confidence = [double]$Gate.confidence
  if ($confidence -lt 0 -or $confidence -gt 1) { throw "Gate confidence must be between 0 and 1." }
  foreach ($field in @("campaign_id", "current_step_id", "current_goal_id", "next_step_id", "next_goal_id", "recommended_next_action")) {
    if ([string]::IsNullOrWhiteSpace([string]$Gate.$field)) { throw "Gate response missing $field." }
  }
  foreach ($field in @("reasons", "blockers", "warnings", "required_human_actions")) {
    if ($null -eq $Gate.$field) { throw "Gate response missing $field array." }
  }
  if ($null -eq $Gate.evidence_reviewed) { throw "Gate response missing evidence_reviewed." }
  if ($null -eq $Gate.safety_assessment) { throw "Gate response missing safety_assessment." }
  foreach ($field in @("safe_to_advance", "safe_to_execute_next_step", "requires_human_approval", "deterministic_veto_expected")) {
    if ($null -eq $Gate.safety_assessment.$field) { throw "Gate safety_assessment missing $field." }
  }
}

function Get-CampaignGateInput {
  if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "$Command requires -CampaignId." }
  $campaignPayload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
  $steps = @($campaignPayload.steps | Sort-Object order)
  $campaign = $campaignPayload.campaign
  $currentStep = @($steps | Where-Object { $_.campaign_step_id -eq $campaign.current_step_id } | Select-Object -First 1)
  if (@($currentStep).Count -eq 0) { $currentStep = @($steps | Where-Object { $_.status -in @("ready", "running") } | Select-Object -First 1) }
  $currentStep = @($currentStep)[0]
  if (-not $currentStep) { throw "Campaign has no current step." }
  $nextStep = @($steps | Where-Object { [int]$_.order -gt [int]$currentStep.order } | Sort-Object order | Select-Object -First 1)
  $nextStep = @($nextStep)[0]
  if (-not $nextStep) { $nextStep = $currentStep }
  $deterministic = (Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance-preview" -Body @{
    human_approved = [bool]$HumanApproved
    human_approval_reason = $HumanApprovalReason
    worktree_dirty = (Get-GitMetadata).dirty
  }).gate
  $status = Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Hygiene", "-ShowCampaigns", "-CampaignId", $CampaignId, "-ShowCampaignSteps", "-Json", "-ColorMode", "Never")
  $hermesHealth = $null
  try {
    $healthArgs = @("-File", ".\scripts\powershell\skybridge-hermes-health.ps1", "-Json")
    if ($HermesEnvFile) { $healthArgs += @("-HermesEnvFile", $HermesEnvFile) }
    if ($HermesApiBase) { $healthArgs += @("-HermesApiBase", $HermesApiBase) }
    $hermesHealth = Invoke-CampaignJsonScript -Arguments $healthArgs
  } catch {}
  $git = Get-GitMetadata
  $inputObject = [pscustomobject]@{
    schema = "skybridge.campaign_gate_input.v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    gate_prompt_version = $PromptVersion
    campaign = $campaign
    current_step = $currentStep
    next_step = $nextStep
    deterministic_gate = $deterministic
    hygiene_summary = $status.hygiene_summary
    task_summary = $status.task_summary
    proposal_summary = $status.proposal_summary
    campaign_summary = $status.campaign_summary
    worker_summary = [pscustomobject]@{
      total = @($status.workers).Count
      online = @($status.workers | Where-Object { $_.status -eq "online" }).Count
      stale = @($status.workers | Where-Object { $_.status -eq "stale" }).Count
      offline = @($status.workers | Where-Object { $_.status -eq "offline" }).Count
    }
    hermes_health = if ($hermesHealth) { [pscustomobject]@{ ok = $hermesHealth.ok; direct_https = $hermesHealth.direct_https; platform = $hermesHealth.platform; model = $hermesHealth.model; token_printed = $false } } else { $null }
    recent_tasks = @($status.tasks | Select-Object -First 10)
    recent_proposals = @($status.proposals | Select-Object -First 10)
    linked_prs = @($currentStep.linked_pr_urls)
    linked_tasks = @($currentStep.linked_task_ids)
    repo = $git
    operator = [pscustomobject]@{
      human_approved = [bool]$HumanApproved
      human_approval_reason = $HumanApprovalReason
    }
  }
  $json = ConvertTo-JsonObject -Value $inputObject
  $inputObject | Add-Member -NotePropertyName input_state_hash -NotePropertyValue (Get-JsonHash -Text $json) -Force
  return $inputObject
}

function New-DefaultHermesGate {
  param($GateInput, [string]$Decision = "advance")
  $current = $GateInput.current_step
  $next = $GateInput.next_step
  [pscustomobject]@{
    schema = "skybridge.campaign_gate.v1"
    decision = $Decision
    confidence = if ($Decision -eq "advance") { 0.82 } else { 0.66 }
    campaign_id = $GateInput.campaign.campaign_id
    current_step_id = $current.campaign_step_id
    current_goal_id = $current.goal_id
    next_step_id = $next.campaign_step_id
    next_goal_id = $next.goal_id
    reasons = @("Fixture gate reviewed structured campaign input.")
    blockers = @()
    warnings = @($GateInput.deterministic_gate.warnings)
    required_human_actions = @()
    evidence_reviewed = [pscustomobject]@{
      active_tasks = [int]$GateInput.task_summary.active
      stale_leases = [int]$GateInput.task_summary.stale_leases
      failed_unrecovered = [int]$GateInput.task_summary.failed_unrecovered
      blocked_tasks = [int]$GateInput.task_summary.blocked
      approved_unconverted_proposals = [int]$GateInput.proposal_summary.approved_unconverted
      current_step_status = [string]$current.status
      linked_prs = @($current.linked_pr_urls)
      linked_tasks = @($current.linked_task_ids)
      validation_summary = "fixture"
      hygiene_summary = $GateInput.hygiene_summary
    }
    safety_assessment = [pscustomobject]@{
      safe_to_advance = ($Decision -eq "advance")
      safe_to_execute_next_step = $false
      requires_human_approval = [bool]$current.advance_gate.requires_human_approval
      deterministic_veto_expected = (@($GateInput.deterministic_gate.blockers).Count -gt 0)
    }
    recommended_next_action = if ($Decision -eq "advance") { "advance_campaign_metadata_only" } else { "hold_campaign" }
    raw_notes = "No worker execution."
  }
}

function Invoke-HermesGate {
  param($GateInput)
  if ($HermesGateFixtureFile) {
    return ConvertFrom-StrictGateJson -Text (Get-Content -Raw -LiteralPath $HermesGateFixtureFile)
  }
  if (-not $UseHermesGate) {
    return New-DefaultHermesGate -GateInput $GateInput -Decision "advance"
  }
  if ($HermesEnvFile) {
    if (-not (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf)) { throw "Hermes env file not found: $HermesEnvFile" }
    . $HermesEnvFile
  } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "load-hermes-env.ps1") -PathType Leaf) {
    . (Join-Path $PSScriptRoot "load-hermes-env.ps1")
  }
  if ($HermesApiBase) { $env:HERMES_API_BASE = $HermesApiBase }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)) { throw "HERMES_API_BASE is missing." }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) { throw "HERMES_API_KEY is missing." }
  $current = $GateInput.current_step
  $next = $GateInput.next_step
  $requiredTemplate = [pscustomobject]@{
    schema = "skybridge.campaign_gate.v1"
    decision = "advance|hold|retry|ask_human|abort"
    confidence = "number 0..1"
    campaign_id = [string]$GateInput.campaign.campaign_id
    current_step_id = [string]$current.campaign_step_id
    current_goal_id = [string]$current.goal_id
    next_step_id = [string]$next.campaign_step_id
    next_goal_id = [string]$next.goal_id
    reasons = @("string")
    blockers = @("string")
    warnings = @("string")
    required_human_actions = @("string")
    evidence_reviewed = @{
      active_tasks = [int]$GateInput.task_summary.active
      stale_leases = [int]$GateInput.task_summary.stale_leases
      failed_unrecovered = [int]$GateInput.task_summary.failed_unrecovered
      blocked_tasks = [int]$GateInput.task_summary.blocked
      approved_unconverted_proposals = [int]$GateInput.proposal_summary.approved_unconverted
      current_step_status = [string]$current.status
      linked_prs = @($current.linked_pr_urls)
      linked_tasks = @($current.linked_task_ids)
      validation_summary = @{}
      hygiene_summary = $GateInput.hygiene_summary
    }
    safety_assessment = @{
      safe_to_advance = $false
      safe_to_execute_next_step = $false
      requires_human_approval = [bool]$current.advance_gate.requires_human_approval
      deterministic_veto_expected = (@($GateInput.deterministic_gate.blockers).Count -gt 0)
    }
    recommended_next_action = "string"
    raw_notes = "string"
  }
  $prompt = @"
You are the SkyBridge campaign gate evaluator. Return strict JSON only. No Markdown.
Schema: skybridge.campaign_gate.v1.
Decision must be one of advance, hold, retry, ask_human, abort.
Deterministic hard blockers are final vetoes. Do not recommend executing the next step; this gate only advances campaign metadata.
You must include every key from this exact output template and copy the provided ids exactly:
$(ConvertTo-JsonObject -Value $requiredTemplate)
Review this redacted campaign gate input:
$(ConvertTo-JsonObject -Value $GateInput)
"@
  $headers = @{ Authorization = "Bearer $env:HERMES_API_KEY"; "Content-Type" = "application/json" }
  $lastError = $null
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    $attemptPrompt = if ($attempt -eq 1) {
      $prompt
    } else {
@"
Your previous response failed strict schema validation: $lastError
Return strict JSON only. No Markdown. Include every required key and copy these ids exactly:
$(ConvertTo-JsonObject -Value $requiredTemplate)
Use this same redacted campaign gate input:
$(ConvertTo-JsonObject -Value $GateInput)
"@
    }
    $body = @{
      model = if ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
      input = $attemptPrompt
      response_format = @{ type = "json_object" }
    }
    $response = Invoke-RestMethod -Method POST -Uri "$($env:HERMES_API_BASE.TrimEnd('/'))/v1/responses" -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 50) -TimeoutSec 180
    try {
      return ConvertFrom-StrictGateJson -Text (Get-StrictHermesText -Response $response)
    } catch {
      $lastError = $_.Exception.Message
      if ($attempt -ge 2) { throw }
    }
  }
}

function Resolve-CampaignGateDecision {
  param($GateInput, $HermesGate)
  $deterministic = $GateInput.deterministic_gate
  $hardBlockers = @($deterministic.blockers)
  if ($GateInput.task_summary.active -gt 0 -and $hardBlockers -notcontains "active_tasks_present") { $hardBlockers += "active_tasks_present" }
  if ($GateInput.task_summary.stale_leases -gt 0 -and $hardBlockers -notcontains "stale_leases_present") { $hardBlockers += "stale_leases_present" }
  if ($GateInput.repo.dirty -eq $true -and $hardBlockers -notcontains "worktree_dirty") { $hardBlockers += "worktree_dirty" }
  $humanRequired = [bool]$GateInput.current_step.advance_gate.requires_human_approval
  $humanPresent = [bool]$GateInput.operator.human_approved
  $detDecision = if ($hardBlockers.Count -gt 0) { "hold" } elseif ($humanRequired -and -not $humanPresent) { "ask_human" } else { "advance" }
  $hermesDecision = [string]$HermesGate.decision
  $final = if ($hardBlockers.Count -gt 0) {
    "hold"
  } elseif ($humanRequired -and -not $humanPresent) {
    "ask_human"
  } elseif ($hermesDecision -eq "advance" -and $detDecision -eq "advance") {
    "advance"
  } elseif ($hermesDecision -in @("abort", "hold", "retry", "ask_human")) {
    $hermesDecision
  } else {
    "hold"
  }
  [pscustomobject]@{
    deterministic_decision = $detDecision
    hermes_decision = $hermesDecision
    final_decision = $final
    decision = $final
    hard_blockers = @($hardBlockers)
    blockers = @($hardBlockers + @($HermesGate.blockers) | Select-Object -Unique)
    warnings = @(@($deterministic.warnings) + @($HermesGate.warnings) | Select-Object -Unique)
    human_approval_required = $humanRequired
    human_approval_present = $humanPresent
    human_approval_reason = $HumanApprovalReason
    advance_allowed = ($final -eq "advance")
    next_step_id = $GateInput.next_step.campaign_step_id
    current_step_id = $GateInput.current_step.campaign_step_id
    input_state_hash = $GateInput.input_state_hash
    prompt_version = $GateInput.gate_prompt_version
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    hermes_gate = $HermesGate
    deterministic_gate = $deterministic
  }
}

function ConvertTo-CampaignImportPayload {
  $manifestPath = Get-GoalPackManifestPath
  $manifestDir = Split-Path -Parent $manifestPath
  $manifest = Read-JsonFile -Path $manifestPath
  $errors = New-Object System.Collections.Generic.List[string]
  if ($manifest.schema -ne "skybridge.campaign.v1") { $errors.Add("manifest schema must be skybridge.campaign.v1") | Out-Null }
  if ([string]::IsNullOrWhiteSpace([string]$manifest.campaign_id)) { $errors.Add("manifest campaign_id is required") | Out-Null }
  if ([string]::IsNullOrWhiteSpace([string]$manifest.title)) { $errors.Add("manifest title is required") | Out-Null }
  $goals = @($manifest.goals)
  $completedExternalDependencies = @($manifest.completed_external_dependencies | ForEach-Object { [string]$_ } | Where-Object { $_ })
  if ($goals.Count -eq 0) { $errors.Add("manifest goals are required") | Out-Null }

  $goalViews = New-Object System.Collections.Generic.List[object]
  $goalIds = New-Object System.Collections.Generic.HashSet[string]
  $orders = New-Object System.Collections.Generic.HashSet[int]
  foreach ($entry in $goals) {
    $pathText = if ($entry -is [string]) { [string]$entry } else { [string]$entry.path }
    if ([string]::IsNullOrWhiteSpace($pathText)) { $errors.Add("goal path is required") | Out-Null; continue }
    $goalPath = Join-Path $manifestDir $pathText
    if (-not (Test-Path -LiteralPath $goalPath -PathType Leaf)) { $errors.Add("goal markdown not found: $pathText") | Out-Null; continue }
    $parsed = Get-MarkdownMetadata -Path $goalPath
    $meta = $parsed.metadata
    if ($meta.schema -ne "skybridge.super_goal.v1") { $errors.Add("$pathText schema must be skybridge.super_goal.v1") | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$meta.goal_id)) { $errors.Add("$pathText goal_id is required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$meta.title)) { $errors.Add("$pathText title is required") | Out-Null }
    $order = 0
    try { $order = [int]$meta.order } catch { $errors.Add("$pathText order must be an integer") | Out-Null }
    if (-not $goalIds.Add([string]$meta.goal_id)) { $errors.Add("duplicate goal_id: $($meta.goal_id)") | Out-Null }
    if (-not $orders.Add($order)) { $errors.Add("duplicate order: $order") | Out-Null }
    if (@($meta.blocked_task_types).Count -eq 0) { $errors.Add("$($meta.goal_id) blocked_task_types are required") | Out-Null }
    if (-not $meta.advance_gate) { $errors.Add("$($meta.goal_id) advance_gate is required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($parsed.body)) { $errors.Add("$($meta.goal_id) markdown body is empty") | Out-Null }
    if (Test-TokenLookingText -Text $parsed.raw) { $errors.Add("$($meta.goal_id) contains token-looking text") | Out-Null }
    if (Test-SensitiveAbsolutePath -Text $parsed.raw) { $errors.Add("$($meta.goal_id) contains sensitive absolute path") | Out-Null }
    $rawDependencies = @($meta.requires | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $goalViews.Add([pscustomobject]@{
      goal_id = [string]$meta.goal_id
      title = [string]$meta.title
      order = $order
      risk = [string]$meta.risk
      task_type = [string]$meta.task_type
      raw_dependencies = @($rawDependencies)
      dependencies = @($rawDependencies)
      markdown_path = $pathText.Replace("\", "/")
      markdown_hash = Get-JsonHash -Text $parsed.raw
      metadata = $meta
      advance_gate = $meta.advance_gate
    }) | Out-Null
  }
  $goalArray = @($goalViews.ToArray())
  $knownIds = @($goalArray | ForEach-Object { $_.goal_id })
  foreach ($goal in $goalArray) {
    $internalDependencies = @()
    foreach ($dependency in @($goal.dependencies)) {
      if ($knownIds -contains $dependency) {
        $internalDependencies += $dependency
      } elseif ($completedExternalDependencies -notcontains $dependency) {
        $errors.Add("dependency $dependency for $($goal.goal_id) does not refer to a goal in the pack or completed_external_dependencies") | Out-Null
      }
    }
    $goal.dependencies = @($internalDependencies)
  }
  $sorted = @($goalArray | Sort-Object order)
  $payload = [pscustomobject]@{
    campaign_id = [string]$manifest.campaign_id
    project_id = if ($manifest.project_id) { [string]$manifest.project_id } else { $ProjectId }
    title = [string]$manifest.title
    description = [string]$manifest.description
    source = if ($manifest.source) { [string]$manifest.source } else { "goal-pack" }
    created_by = if ($manifest.created_by) { [string]$manifest.created_by } else { "operator" }
    imported_from = (Resolve-Path -LiteralPath $manifestPath).Path
    goal_pack_hash = Get-JsonHash -Text (Get-Content -Raw -LiteralPath $manifestPath)
    safety_policy = $manifest.safety_policy
    metadata = [pscustomobject]@{ dependency_order = @($sorted.goal_id); default_advance_gates = $manifest.default_advance_gates; stop_conditions = $manifest.stop_conditions }
    goals = @($sorted)
  }
  [pscustomobject]@{ ok = ($errors.Count -eq 0); errors = @($errors.ToArray()); manifest_path = $manifestPath; goal_count = $sorted.Count; payload = $payload }
}

function Write-CampaignResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 80 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.campaign) {
    "Campaign:     $($Result.campaign.campaign_id)"
    "Status:       $($Result.campaign.status)"
    "CurrentStep:  $($Result.campaign.current_step_id)"
    "Title:        $($Result.campaign.title)"
  }
  if ($Result.validation) {
    "Validation:   $($Result.validation.ok)"
    if ($Result.validation.errors) { foreach ($errorItem in @($Result.validation.errors)) { "  error: $errorItem" } }
  }
  if ($Result.gate) {
    "Gate:         $(if ($Result.gate.final_decision) { $Result.gate.final_decision } else { $Result.gate.decision })"
    if ($Result.gate.deterministic_decision) { "Deterministic:$($Result.gate.deterministic_decision)" }
    if ($Result.gate.hermes_decision) { "Hermes:       $($Result.gate.hermes_decision)" }
    if ($Result.gate.reason) { "Reason:       $($Result.gate.reason)" }
    if ($Result.gate.blockers) { "Blockers:     $(@($Result.gate.blockers) -join ', ')" }
    if ($Result.gate.warnings) { "Warnings:     $(@($Result.gate.warnings) -join ', ')" }
    if ($Result.gate.input_state_hash) { "InputHash:    $($Result.gate.input_state_hash)" }
  }
  if ($Result.steps) {
    "Steps:        $(@($Result.steps).Count)"
    foreach ($step in @($Result.steps | Sort-Object order)) {
      "  $($step.order). $($step.goal_id) [$($step.status)] $($step.title)"
    }
  }
  if ($Result.campaigns) {
    "Campaigns:    $(@($Result.campaigns).Count)"
    foreach ($campaign in @($Result.campaigns)) {
      "  $($campaign.campaign_id) [$($campaign.status)] $($campaign.current_step_id) $($campaign.title)"
    }
  }
  "TokenPrinted: false"
}

$script:Config = New-CampaignApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$effectiveDryRun = $DryRun -or -not $Apply
$result = $null

switch ($Command) {
  "init" {
    $target = if ($GoalPackDir) { $GoalPackDir } else { "goals/bootstrap-mvp" }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; would_create = $target }
  }
  "validate-pack" {
    $validation = ConvertTo-CampaignImportPayload
    $result = [pscustomobject]@{ ok = $validation.ok; command = $Command; mode = "offline"; project_id = $ProjectId; token_printed = $false; validation = $validation; payload = $validation.payload }
  }
  "import" {
    $validation = ConvertTo-CampaignImportPayload
    if (-not $validation.ok) { throw "Goal pack validation failed: $(@($validation.errors) -join '; ')" }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; validation = $validation; would_import = $validation.payload }
    } else {
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns" -Body $validation.payload
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.steps); validation = $validation }
    }
  }
  "list" {
    $path = "/v1/campaigns?project_id=$([uri]::EscapeDataString($ProjectId))"
    $payload = Invoke-CampaignApi -Method GET -Path $path
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaigns = @($payload.campaigns) }
  }
  "show" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "show requires -CampaignId." }
    $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.steps) }
  }
  "steps" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "steps requires -CampaignId." }
    $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps"
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; steps = @($payload.steps) }
  }
  "status" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "status requires -CampaignId." }
    $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
    $gate = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance-preview" -Body @{ human_approved = [bool]$HumanApproved }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.steps); gate = $gate.gate }
  }
  "advance-preview" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "advance-preview requires -CampaignId." }
    $gate = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance-preview" -Body @{ human_approved = [bool]$HumanApproved }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; gate = $gate.gate }
  }
  "gate-preview" {
    $gateInput = Get-CampaignGateInput
    $hermesGate = New-DefaultHermesGate -GateInput $gateInput -Decision "advance"
    $finalGate = Resolve-CampaignGateDecision -GateInput $gateInput -HermesGate $hermesGate
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; gate_input = $gateInput; gate = $finalGate }
  }
  "hermes-gate-preview" {
    $gateInput = Get-CampaignGateInput
    $hermesGate = Invoke-HermesGate -GateInput $gateInput
    $finalGate = Resolve-CampaignGateDecision -GateInput $gateInput -HermesGate $hermesGate
    if ($SaveGateInput) {
      $dir = Split-Path -Parent $SaveGateInput
      if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $gateInput | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $SaveGateInput -Encoding UTF8
    }
    if ($SaveGateOutput) {
      $dir = Split-Path -Parent $SaveGateOutput
      if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $finalGate | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $SaveGateOutput -Encoding UTF8
    }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; gate_input = $gateInput; hermes_gate = $hermesGate; gate = $finalGate }
  }
  "start" { $targetStatusCommand = "start" }
  "pause" { $targetStatusCommand = "pause" }
  "hold" { $targetStatusCommand = "hold" }
  "resume" { $targetStatusCommand = "resume" }
  "advance" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "advance requires -CampaignId." }
    if ($effectiveDryRun) {
      $gate = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance-preview" -Body @{ human_approved = [bool]$HumanApproved }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; gate = $gate.gate }
    } else {
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance" -Body @{ confirm_advance = $true; human_approved = [bool]$HumanApproved }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step); gate = $payload.gate }
    }
  }
  "advance-with-gate" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "advance-with-gate requires -CampaignId." }
    if ($HumanApproved -and [string]::IsNullOrWhiteSpace($HumanApprovalReason)) { throw "advance-with-gate -HumanApproved requires -HumanApprovalReason." }
    $gateInput = Get-CampaignGateInput
    $hermesGate = Invoke-HermesGate -GateInput $gateInput
    $finalGate = Resolve-CampaignGateDecision -GateInput $gateInput -HermesGate $hermesGate
    if ($SaveGateInput) {
      $dir = Split-Path -Parent $SaveGateInput
      if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $gateInput | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $SaveGateInput -Encoding UTF8
    }
    if ($SaveGateOutput) {
      $dir = Split-Path -Parent $SaveGateOutput
      if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $finalGate | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $SaveGateOutput -Encoding UTF8
    }
    if ($effectiveDryRun -or $finalGate.final_decision -ne "advance") {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; gate_input = $gateInput; hermes_gate = $hermesGate; gate = $finalGate; would_advance = ($finalGate.final_decision -eq "advance") }
    } else {
      $advancePayload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/advance" -Body @{
        confirm_advance = $true
        human_approved = [bool]$HumanApproved
        human_approval_reason = $HumanApprovalReason
        gate_result = $finalGate
      }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $advancePayload.campaign; steps = @($advancePayload.step); gate = $finalGate; advanced = $true }
    }
  }
  "attach-gate-evidence" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "attach-gate-evidence requires -CampaignId." }
    $gateInput = Get-CampaignGateInput
    $hermesGate = Invoke-HermesGate -GateInput $gateInput
    $finalGate = Resolve-CampaignGateDecision -GateInput $gateInput -HermesGate $hermesGate
    $targetStepId = if ($StepId) { $StepId } else { [string]$gateInput.current_step.campaign_step_id }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $targetStepId; gate = $finalGate; would_attach_gate_evidence = $true }
    } else {
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($targetStepId))/attach-evidence" -Body @{
        evidence_summary = @{
          summary = "Campaign gate evaluated: final_decision=$($finalGate.final_decision); deterministic=$($finalGate.deterministic_decision); hermes=$($finalGate.hermes_decision)"
          created_at = (Get-Date).ToUniversalTime().ToString("o")
          input_state_hash = $finalGate.input_state_hash
          prompt_version = $finalGate.prompt_version
          gate_result = $finalGate
        }
      }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step); gate = $finalGate }
    }
  }
  "complete-step" {
    if ([string]::IsNullOrWhiteSpace($CampaignId) -or [string]::IsNullOrWhiteSpace($StepId)) { throw "complete-step requires -CampaignId and -StepId." }
    if (-not $EvidenceSummary -and $LinkedTaskIds.Count -eq 0 -and $LinkedPrUrls.Count -eq 0) { throw "complete-step requires -EvidenceSummary, -LinkedTaskIds, or -LinkedPrUrls." }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $StepId; would_complete = $true }
    } else {
      $body = @{ linked_task_ids = @($LinkedTaskIds); linked_pr_urls = @($LinkedPrUrls) }
      if ($EvidenceSummary) { $body.evidence_summary = @{ summary = $EvidenceSummary; created_at = (Get-Date).ToUniversalTime().ToString("o") } }
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($StepId))/complete" -Body $body
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step) }
    }
  }
  "fail-step" {
    if ([string]::IsNullOrWhiteSpace($CampaignId) -or [string]::IsNullOrWhiteSpace($StepId)) { throw "fail-step requires -CampaignId and -StepId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "fail-step requires -Reason." }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $StepId; would_fail = $true; reason = $Reason }
    } else {
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($StepId))/fail" -Body @{ reason = $Reason }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step) }
    }
  }
  "attach-evidence" {
    if ([string]::IsNullOrWhiteSpace($CampaignId) -or [string]::IsNullOrWhiteSpace($StepId)) { throw "attach-evidence requires -CampaignId and -StepId." }
    if (-not $EvidenceSummary -and $LinkedTaskIds.Count -eq 0 -and $LinkedPrUrls.Count -eq 0) { throw "attach-evidence requires -EvidenceSummary, -LinkedTaskIds, or -LinkedPrUrls." }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $StepId; would_attach_evidence = $true }
    } else {
      $body = @{ linked_task_ids = @($LinkedTaskIds); linked_pr_urls = @($LinkedPrUrls) }
      if ($EvidenceSummary) { $body.evidence_summary = @{ summary = $EvidenceSummary; created_at = (Get-Date).ToUniversalTime().ToString("o") } }
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($StepId))/attach-evidence" -Body $body
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step) }
    }
  }
  "export-report" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "export-report requires -CampaignId." }
    $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.steps); generated_at = (Get-Date).ToUniversalTime().ToString("o") }
  }
}

if ($targetStatusCommand) {
  if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "$Command requires -CampaignId." }
  if ($Command -in @("hold") -and [string]::IsNullOrWhiteSpace($Reason)) { throw "$Command requires -Reason." }
  if ($effectiveDryRun) {
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; would_call = $targetStatusCommand; reason = $Reason }
  } else {
    $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/$targetStatusCommand" -Body @{ reason = $Reason }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.steps) }
  }
}

if (-not $result) { throw "Command did not produce a result: $Command" }
Write-CampaignResult -Result $result
