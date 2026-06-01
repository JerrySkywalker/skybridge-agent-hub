[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("init", "validate-pack", "import", "list", "show", "steps", "status", "start", "pause", "hold", "resume", "advance-preview", "advance", "gate-preview", "hermes-gate-preview", "advance-with-gate", "attach-gate-evidence", "execute-preview", "execute-step", "link-task", "attach-execution-evidence", "step-report", "complete-step", "fail-step", "attach-evidence", "export-report", "run-next", "run-until-hold", "run-until-complete", "runner-status", "runner-report", "runner-stop", "runner-hold", "runner-unlock")]
  [string]$Command = "status",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId,
  [string]$GoalPackDir,
  [string]$ManifestFile,
  [string]$StepId,
  [string]$GoalId,
  [string]$WorkerId,
  [string]$WorkerProfile,
  [string]$TaskId,
  [string]$ExecutionTaskType = "docs",
  [string[]]$ExpectedFiles = @(),
  [switch]$RetryAttempt,
  [switch]$AcknowledgeMarkdownHashMismatch,
  [switch]$Run,
  [string]$TokenFile,
  [string]$TokenEnvVar,
  [switch]$UseHermesGate,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [string]$HermesGateFixtureFile,
  [string]$PromptVersion = "campaign-gate-v1",
  [string]$HumanApprovalReason,
  [string]$RunnerApprovalScope,
  [string]$RunnerUnlockReason,
  [int]$MaxSteps = 1,
  [int]$MaxTasks = 1,
  [int]$MaxRuntimeMinutes = 30,
  [int]$PollIntervalSeconds = 30,
  [int]$IdleTimeoutSeconds = 600,
  [switch]$StopOnFailure,
  [switch]$StopOnHumanRequired,
  [switch]$AllowAutoMerge,
  [switch]$AllowEvidenceRepair,
  [switch]$AllowServerDeploy,
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
Treat deterministic warnings as warnings, not blockers. Warning-only conditions such as failed_unrecovered_tasks_present, blocked_tasks_present, approved_unconverted_proposals_present, recovered_tasks_present, and worker_offline do not block metadata-only campaign advance by themselves.
safe_to_advance means safe to update campaign step metadata. safe_to_execute_next_step must remain false unless a separate worker execution gate exists.
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
Treat warning-only hygiene conditions as warnings, not blockers. Metadata-only advance can be safe even when execution of the next step is not safe.
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

function Resolve-CampaignStepMarkdownPath {
  param($Campaign, $Step)
  $pathText = [string]$Step.markdown_path
  if ([string]::IsNullOrWhiteSpace($pathText)) { throw "Campaign step has no markdown_path: $($Step.campaign_step_id)" }
  if ([System.IO.Path]::IsPathRooted($pathText) -and (Test-Path -LiteralPath $pathText -PathType Leaf)) { return (Resolve-Path -LiteralPath $pathText).Path }
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($ManifestFile) {
    $manifestPath = (Resolve-Path -LiteralPath $ManifestFile -ErrorAction Stop).Path
    $candidates.Add((Join-Path (Split-Path -Parent $manifestPath) $pathText)) | Out-Null
  }
  if ($GoalPackDir) { $candidates.Add((Join-Path $GoalPackDir $pathText)) | Out-Null }
  if ($Campaign.imported_from -and (Test-Path -LiteralPath ([string]$Campaign.imported_from) -PathType Leaf)) {
    $candidates.Add((Join-Path (Split-Path -Parent ([string]$Campaign.imported_from)) $pathText)) | Out-Null
  }
  $candidates.Add((Join-Path (Join-Path "goals" ([string]$Campaign.campaign_id)) $pathText)) | Out-Null
  $candidates.Add((Join-Path "goals/bootstrap-mvp" $pathText)) | Out-Null
  foreach ($candidate in @($candidates.ToArray())) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  throw "Campaign step markdown not found for $($Step.campaign_step_id): $pathText"
}

function Get-CampaignExecutionExpectedFiles {
  param($Step)
  if (@($ExpectedFiles).Count -gt 0) { return @($ExpectedFiles | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ }) }
  $goalId = ([string]$Step.goal_id).ToLowerInvariant()
  if ($goalId -eq "super-187-bootstrap-campaign-mvp-hardening") {
    return @(
      "docs/dev/CAMPAIGN_STEP_EXECUTOR_PILOT.md",
      "docs/dev/BOOTSTRAP_CAMPAIGN_MVP.md",
      "docs/dev/PROGRESS.md",
      "docs/orchestrator/SELF_BOOTSTRAP_SUPERVISOR.md",
      "docs/orchestrator/WORKER_PROFILE_RUNBOOK.md"
    )
  }
  return @("docs/dev/$($goalId.ToUpperInvariant()).md".ToLowerInvariant())
}

function Test-CampaignExecutionPaths {
  param([string]$TaskType, [string[]]$Files)
  $normalized = @($Files | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ })
  if ($normalized.Count -lt 1) { return @{ ok = $false; reason = "expected_files_required" } }
  foreach ($file in $normalized) {
    if ($file -match "(?i)(^|/)(\.env|id_rsa|secrets?|tokens?|private-key)" -or $file -match "(?i)^(deploy/|\.github/settings|server-root|/opt/|C:/Users/.*/\.skybridge)") {
      return @{ ok = $false; reason = "unsafe_expected_file:$file" }
    }
    if ($TaskType -eq "docs" -and $file -notlike "docs/*") { return @{ ok = $false; reason = "docs_task_file_outside_docs:$file" } }
    if ($TaskType -eq "local-smoke" -and $file -notmatch "^scripts/powershell/smoke-[^/]+\.ps1$") { return @{ ok = $false; reason = "local_smoke_file_not_safe:$file" } }
    if ($TaskType -eq "refactor" -and $file -notlike "docs/*" -and $file -notlike "scripts/powershell/*" -and $file -notlike "apps/server/src/*" -and $file -notlike "packages/event-schema/src/*") {
      return @{ ok = $false; reason = "refactor_file_outside_allowed_paths:$file" }
    }
  }
  return @{ ok = $true; reason = "paths_ok" }
}

function Get-CampaignExecutionContext {
  if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "$Command requires -CampaignId." }
  $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
  $campaign = $payload.campaign
  $steps = @($payload.steps | Sort-Object order)
  if (-not $campaign) { throw "Campaign not found: $CampaignId" }
  $step = $null
  if ($StepId) { $step = @($steps | Where-Object { $_.campaign_step_id -eq $StepId })[0] }
  elseif ($GoalId) { $step = @($steps | Where-Object { $_.goal_id -eq $GoalId })[0] }
  elseif ($campaign.current_step_id) { $step = @($steps | Where-Object { $_.campaign_step_id -eq $campaign.current_step_id })[0] }
  if (-not $step) { throw "Campaign step not found. Supply -StepId or -GoalId." }
  $markdownPath = Resolve-CampaignStepMarkdownPath -Campaign $campaign -Step $step
  $rawMarkdown = Get-Content -Raw -LiteralPath $markdownPath
  $parsedMarkdown = Get-MarkdownMetadata -Path $markdownPath
  $hash = Get-JsonHash -Text $rawMarkdown
  $expected = @(Get-CampaignExecutionExpectedFiles -Step $step)
  $executionTaskType = $ExecutionTaskType.ToLowerInvariant()
  $pathCheck = Test-CampaignExecutionPaths -TaskType $executionTaskType -Files $expected
  $status = Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-Hygiene", "-ShowCampaigns", "-CampaignId", $CampaignId, "-ShowCampaignSteps", "-Json", "-ColorMode", "Never")
  $repo = Get-GitMetadata
  [pscustomobject]@{
    campaign = $campaign
    steps = @($steps)
    step = $step
    markdown_path = $markdownPath
    markdown_hash = $hash
    markdown_hash_matches = ([string]$step.markdown_hash -eq $hash)
    markdown = $rawMarkdown
    markdown_body = $parsedMarkdown.body
    expected_files = @($expected)
    execution_task_type = $executionTaskType
    path_check = $pathCheck
    status = $status
    repo = $repo
  }
}

function Get-CampaignExecutionBlockers {
  param($Context)
  $blockers = New-Object System.Collections.Generic.List[string]
  $step = $Context.step
  $campaign = $Context.campaign
  $status = $Context.status
  $taskSummary = $status.task_summary
  $hygiene = $status.hygiene_summary
  if ($campaign.current_step_id -and $step.campaign_step_id -ne $campaign.current_step_id) { $blockers.Add("step_not_current") | Out-Null }
  if ([string]$campaign.status -in @("running", "failed", "aborted")) { $blockers.Add("campaign_status_$($campaign.status)") | Out-Null }
  if ([string]$step.status -notin @("ready", "running", "needs_human")) { $blockers.Add("step_not_ready:$($step.status)") | Out-Null }
  if ([string]$step.status -in @("completed", "recovered", "skipped") -and -not $RetryAttempt) { $blockers.Add("step_already_done") | Out-Null }
  if ($taskSummary.active -gt 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($hygiene.stale_leases -gt 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($status.control.state -eq "running") { $blockers.Add("project_control_running") | Out-Null }
  foreach ($dependencyId in @($step.dependencies)) {
    $dependency = @($Context.steps | Where-Object { $_.goal_id -eq $dependencyId -or $_.campaign_step_id -eq $dependencyId })[0]
    if (-not $dependency -or [string]$dependency.status -notin @("completed", "recovered", "skipped")) { $blockers.Add("dependency_not_complete:$dependencyId") | Out-Null }
  }
  if (-not $Context.markdown_hash_matches -and -not $AcknowledgeMarkdownHashMismatch) { $blockers.Add("markdown_hash_mismatch") | Out-Null }
  if (-not $Context.path_check.ok) { $blockers.Add([string]$Context.path_check.reason) | Out-Null }
  if ($Context.repo.dirty -eq $true) { $blockers.Add("worktree_dirty") | Out-Null }
  $linkedTaskIds = @($step.linked_task_ids | Where-Object { $_ })
  if ($linkedTaskIds.Count -gt 0 -and -not $RetryAttempt) { $blockers.Add("duplicate_linked_task") | Out-Null }
  foreach ($taskIdItem in $linkedTaskIds) {
    try {
      $taskPayload = Invoke-CampaignApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString([string]$taskIdItem))"
      if ([string]$taskPayload.task.status -in @("queued", "claimed", "running")) { $blockers.Add("linked_active_task:$taskIdItem") | Out-Null }
      if ($taskPayload.task.result.pr_url -and [string]$taskPayload.task.status -in @("queued", "claimed", "running", "failed")) { $blockers.Add("linked_open_or_unresolved_pr:$taskIdItem") | Out-Null }
    } catch {}
  }
  $blockedTaskTypes = @($step.metadata.blocked_task_types | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if ($blockedTaskTypes -contains $Context.execution_task_type) { $blockers.Add("blocked_task_type:$($Context.execution_task_type)") | Out-Null }
  $allowedTaskTypes = @($step.metadata.allowed_task_types | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if ($allowedTaskTypes.Count -gt 0 -and $allowedTaskTypes -notcontains $Context.execution_task_type) { $blockers.Add("task_type_not_allowed:$($Context.execution_task_type)") | Out-Null }
  if ($WorkerId) {
    $worker = @($status.workers | Where-Object { $_.worker_id -eq $WorkerId -or $_.id -eq $WorkerId })[0]
    if (-not $worker -or [string]$worker.status -ne "online") { $blockers.Add("worker_unavailable:$WorkerId") | Out-Null }
  } elseif (@($status.workers | Where-Object { $_.status -eq "online" }).Count -lt 1) {
    $blockers.Add("worker_unavailable") | Out-Null
  }
  @($blockers.ToArray() | Select-Object -Unique)
}

function New-CampaignExecutionTaskPayload {
  param($Context)
  $step = $Context.step
  $taskIdValue = if ($TaskId) { $TaskId } else { "campaign-step-$(([string]$step.goal_id).ToLowerInvariant() -replace '[^a-z0-9]+','-')-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))" }
  $taskType = $Context.execution_task_type
  $requiredCapabilities = if ($taskType -eq "local-smoke") { @("codex", "powershell", "windows") } else { @("codex", "git", "gh") }
  $body = @"
This task is executing a campaign step. Do not advance the campaign yourself unless explicitly instructed by SkyBridge gate.

Campaign: $($Context.campaign.campaign_id)
Step: $($step.campaign_step_id)
Goal: $($step.goal_id)
Source markdown: $($Context.markdown_path)
Markdown hash: $($Context.markdown_hash)

Safety boundaries:
- Do not change production deployment, server root config, secrets, GitHub settings, or branch protection.
- Do not execute Super 184B.
- Keep work bounded to the expected files listed below.
- Create a draft/manual child PR and report validation evidence.

Expected files:
$(@($Context.expected_files | ForEach-Object { "- $_" }) -join "`n")

Required evidence:
- draft parent or child PR URL;
- validation summary;
- campaign step result summary;
- CI/merge/evidence status when available.

Full Super Goal markdown:

$($Context.markdown)
"@
  [pscustomobject]@{
    task_id = $taskIdValue
    project_id = $ProjectId
    title = "Campaign step execution: $($step.title)"
    body = $body
    prompt_summary = "Execute campaign step $($step.goal_id) from $($Context.campaign.campaign_id); do not advance campaign metadata."
    risk = "low"
    source = "custom"
    task_type = $taskType
    allowed_paths = @($Context.expected_files)
    blocked_paths = @("deploy/**", ".env", "**/.env", "**/*token*", "**/*secret*", ".github/settings/**")
    validation = @("pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/validate-powershell.ps1", "just check")
    required_capabilities = @($requiredCapabilities)
    planner_metadata = @{
      adapter = "campaign-step-executor"
      decision = "continue"
      reason = "Campaign step execution task generated from imported Super Goal markdown."
      task_type = $taskType
      allowed_paths = @($Context.expected_files)
      expected_files = @($Context.expected_files)
      blocked_paths = @("deploy/**", ".env", "**/.env", "**/*token*", "**/*secret*", ".github/settings/**")
      validation = @("validate-powershell.ps1", "just check")
      stop_criteria_status = @("completed", "recovered", "blocked", "failed")
      source_run_id = "$($Context.campaign.campaign_id):$($step.campaign_step_id)"
      source_campaign_id = $Context.campaign.campaign_id
      source_campaign_step_id = $step.campaign_step_id
      source_goal_id = $step.goal_id
      markdown_path = $step.markdown_path
      markdown_hash = $Context.markdown_hash
      expected_outputs = @($step.metadata.expected_outputs)
      advance_gate = $step.advance_gate
      created_at = (Get-Date).ToUniversalTime().ToString("o")
      raw_response_included = $false
      secrets_included = $false
    }
  }
}

function New-CampaignExecutionPreview {
  $context = Get-CampaignExecutionContext
  $blockers = @(Get-CampaignExecutionBlockers -Context $context)
  $task = New-CampaignExecutionTaskPayload -Context $context
  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    command = $Command
    mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
    project_id = $ProjectId
    token_printed = $false
    campaign_id = $context.campaign.campaign_id
    step_id = $context.step.campaign_step_id
    goal_id = $context.step.goal_id
    markdown_path = $context.markdown_path
    markdown_hash = $context.markdown_hash
    markdown_hash_matches = $context.markdown_hash_matches
    blockers = @($blockers)
    expected_files = @($context.expected_files)
    task = $task
    would_create_task = ($blockers.Count -eq 0)
    would_run_worker = [bool]$Run
  }
}

function Get-CampaignRunnerRoot {
  $root = Join-Path ".agent" "campaign-runners"
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  return $root
}

function Get-CampaignRunnerStatePath {
  param([string]$TargetCampaignId = $CampaignId)
  if ([string]::IsNullOrWhiteSpace($TargetCampaignId)) { throw "$Command requires -CampaignId." }
  Join-Path (Get-CampaignRunnerRoot) (($TargetCampaignId -replace '[^A-Za-z0-9_.-]', '_') + ".runner.json")
}

function Get-CampaignRunnerLockPath {
  param([string]$TargetCampaignId = $CampaignId, [string]$TargetProjectId = $ProjectId)
  if ([string]::IsNullOrWhiteSpace($TargetCampaignId)) { throw "$Command requires -CampaignId." }
  $dir = Join-Path (Get-CampaignRunnerRoot) "locks"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $name = (($TargetProjectId + "__" + $TargetCampaignId) -replace '[^A-Za-z0-9_.-]', '_') + ".lock.json"
  Join-Path $dir $name
}

function Read-CampaignRunnerJson {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-CampaignRunnerJson {
  param($Value, [string]$Path)
  $dir = Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-CampaignRunnerNow {
  (Get-Date).ToUniversalTime().ToString("o")
}

function Get-CampaignRunnerLockStatus {
  param($Lock)
  if (-not $Lock) { return "none" }
  if ($Lock.lock_status -and $Lock.lock_status -ne "active") { return [string]$Lock.lock_status }
  try {
    $expiresAt = [datetimeoffset]::Parse([string]$Lock.expires_at).UtcDateTime
    if ($expiresAt -lt [datetime]::UtcNow) { return "stale" }
  } catch {
    return "stale"
  }
  return "active"
}

function Get-CampaignRunnerApprovalScope {
  $scope = $null
  if (-not [string]::IsNullOrWhiteSpace($RunnerApprovalScope)) {
    if (Test-Path -LiteralPath $RunnerApprovalScope -PathType Leaf) {
      $scope = Get-Content -Raw -LiteralPath $RunnerApprovalScope | ConvertFrom-Json
    } else {
      $scope = $RunnerApprovalScope | ConvertFrom-Json
    }
  } elseif ($HumanApproved) {
    $scope = [pscustomobject]@{
      approved_by = "operator"
      approved_at = Get-CampaignRunnerNow
      campaign_id = $CampaignId
      allowed_goal_ids = @("*")
      max_steps = $MaxSteps
      max_tasks = $MaxTasks
      max_runtime_minutes = $MaxRuntimeMinutes
      allowed_task_types = @("docs", "local-smoke", "refactor", "frontend", "backend", "test")
      blocked_task_types = @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection")
      allowed_paths = @("docs/**", "scripts/powershell/**", "apps/**", "packages/**", "goals/**")
      human_approval_reason = $HumanApprovalReason
      expires_at = (Get-Date).ToUniversalTime().AddMinutes([Math]::Max(1, $MaxRuntimeMinutes)).ToString("o")
      revoked_at = $null
    }
  }
  if ($scope) {
    $json = $scope | ConvertTo-Json -Depth 40 -Compress
    $scope | Add-Member -NotePropertyName scope_hash -NotePropertyValue (Get-JsonHash -Text $json) -Force
  }
  return $scope
}

function Test-CampaignRunnerApproval {
  param($Step, $Scope)
  if (-not $Scope) {
    return [pscustomobject]@{
      ok = $false
      approval_type = "none"
      blockers = @()
      task_type = "unknown"
      scope_hash = $null
    }
  }
  $blocked = @()
  $taskType = ([string]$Step.metadata.task_type).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($taskType) -or $taskType -eq "super-goal") { $taskType = "docs" }
  $blockedTypes = @($Scope.blocked_task_types | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if ($blockedTypes -contains $taskType) { $blocked += "blocked_task_type:$taskType" }
  $stepBlockedTypes = @($Step.metadata.blocked_task_types | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if (@($stepBlockedTypes | Where-Object { $_ -in @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection") }).Count -gt 0 -and $taskType -in @("production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection")) {
    $blocked += "high_risk_task_type:$taskType"
  }
  $allowedGoalIds = @($Scope.allowed_goal_ids | ForEach-Object { [string]$_ })
  if ($allowedGoalIds.Count -gt 0 -and $allowedGoalIds -notcontains "*" -and $allowedGoalIds -notcontains [string]$Step.goal_id) {
    $blocked += "goal_not_in_runner_approval_scope:$($Step.goal_id)"
  }
  if ($Scope.campaign_id -and [string]$Scope.campaign_id -ne [string]$Step.campaign_id) { $blocked += "campaign_not_in_runner_approval_scope" }
  if ($Scope.revoked_at) { $blocked += "runner_approval_revoked" }
  if ($Scope.expires_at) {
    try {
      if ([datetimeoffset]::Parse([string]$Scope.expires_at).UtcDateTime -lt [datetime]::UtcNow) { $blocked += "runner_approval_expired" }
    } catch {
      $blocked += "runner_approval_expiry_invalid"
    }
  }
  [pscustomobject]@{
    ok = ($blocked.Count -eq 0)
    approval_type = if ($Scope) { "delegated_runner_approval" } else { "none" }
    blockers = @($blocked)
    task_type = $taskType
    scope_hash = if ($Scope) { $Scope.scope_hash } else { $null }
  }
}

function Get-CampaignRunnerSnapshot {
  if ($GoalPackDir -or $ManifestFile) {
    $validation = ConvertTo-CampaignImportPayload
    if (-not $validation.ok) { throw "Goal pack validation failed: $(@($validation.errors) -join '; ')" }
    $campaign = $validation.payload
    $now = Get-CampaignRunnerNow
    $steps = @($validation.payload.goals | Sort-Object order | ForEach-Object {
      [pscustomobject]@{
        campaign_step_id = "$($validation.payload.campaign_id):$($_.goal_id)"
        campaign_id = $validation.payload.campaign_id
        project_id = $validation.payload.project_id
        goal_id = $_.goal_id
        title = $_.title
        order = $_.order
        status = if ([int]$_.order -eq 1) { "ready" } else { "pending" }
        dependencies = @($_.dependencies)
        markdown_path = $_.markdown_path
        markdown_hash = $_.markdown_hash
        metadata = $_.metadata
        advance_gate = $_.advance_gate
        linked_task_ids = @()
        linked_pr_urls = @()
        created_at = $now
        updated_at = $now
      }
    })
    $campaignObject = [pscustomobject]@{
      campaign_id = $validation.payload.campaign_id
      project_id = $validation.payload.project_id
      title = $validation.payload.title
      source = $validation.payload.source
      status = "ready"
      current_step_id = if ($steps.Count -gt 0) { $steps[0].campaign_step_id } else { $null }
      safety_policy = $validation.payload.safety_policy
      metadata = $validation.payload.metadata
      created_at = $now
      updated_at = $now
    }
    return [pscustomobject]@{ campaign = $campaignObject; steps = @($steps); fixture = $true; validation = $validation }
  }
  $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
  return [pscustomobject]@{ campaign = $payload.campaign; steps = @($payload.steps | Sort-Object order); fixture = $false; validation = $null }
}

function Get-CampaignRunnerHygiene {
  if ($GoalPackDir -or $ManifestFile) {
    return [pscustomobject]@{ active_tasks = 0; stale_leases = 0; stale_locks = 0; stop_requested = $false; project_control = "paused"; blockers = @() }
  }
  $status = Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Hygiene", "-ShowLeases", "-ShowLocks", "-Json", "-ColorMode", "Never")
  [pscustomobject]@{
    active_tasks = [int]$status.task_summary.active
    stale_leases = [int]$status.task_summary.stale_leases
    stale_locks = if ($status.hygiene_summary.stale_locks) { [int]$status.hygiene_summary.stale_locks } else { 0 }
    stop_requested = [bool]$status.control.stop_requested
    project_control = [string]$status.control.state
    blockers = @()
    raw = $status
  }
}

function New-CampaignRunnerState {
  param($Snapshot, [string]$RunnerStatus = "running")
  $now = Get-CampaignRunnerNow
  [pscustomobject]@{
    schema = "skybridge.campaign_runner_state.v1"
    runner_id = "runner_$([Guid]::NewGuid().ToString("n"))"
    campaign_id = $Snapshot.campaign.campaign_id
    project_id = $Snapshot.campaign.project_id
    runner_status = $RunnerStatus
    current_step_id = $Snapshot.campaign.current_step_id
    started_at = $now
    updated_at = $now
    stopped_at = $null
    max_steps = $MaxSteps
    max_tasks = $MaxTasks
    max_runtime_minutes = $MaxRuntimeMinutes
    steps_attempted = 0
    steps_completed = 0
    tasks_attempted = 0
    tasks_completed = 0
    last_decision = $null
    last_error = $null
    hold_reason = $null
    resume_token = $null
    resume_state_hash = $null
    operator_approval_scope = $null
    audit_log = @()
  }
}

function Add-CampaignRunnerAudit {
  param($State, [string]$Decision, [string]$StepId, [string]$Reason = "")
  $entry = [pscustomobject]@{ at = Get-CampaignRunnerNow; decision = $Decision; step_id = $StepId; reason = $Reason }
  $State.audit_log = @($State.audit_log) + @($entry)
  $State.updated_at = $entry.at
  $State.last_decision = $Decision
  $State.resume_state_hash = Get-JsonHash -Text ($State | ConvertTo-Json -Depth 80 -Compress)
}

function Acquire-CampaignRunnerLock {
  param($Snapshot, $State)
  $lockPath = Get-CampaignRunnerLockPath -TargetCampaignId $Snapshot.campaign.campaign_id -TargetProjectId $Snapshot.campaign.project_id
  $existing = Read-CampaignRunnerJson -Path $lockPath
  $existingStatus = Get-CampaignRunnerLockStatus -Lock $existing
  if ($existingStatus -eq "active") { throw "Active campaign runner lock exists for $($Snapshot.campaign.campaign_id)." }
  if ($existingStatus -eq "stale" -and -not ($Command -eq "runner-unlock" -and $Apply)) { throw "Stale campaign runner lock blocks auto-run until inspected: $lockPath" }
  $now = Get-CampaignRunnerNow
  $lock = [pscustomobject]@{
    schema = "skybridge.campaign_runner_lock.v1"
    campaign_lock_id = "lock_$([Guid]::NewGuid().ToString("n"))"
    campaign_id = $Snapshot.campaign.campaign_id
    project_id = $Snapshot.campaign.project_id
    lock_owner = $State.runner_id
    lock_status = "active"
    created_at = $now
    heartbeat_at = $now
    expires_at = (Get-Date).ToUniversalTime().AddMinutes([Math]::Max(1, $MaxRuntimeMinutes)).ToString("o")
    release_reason = $null
  }
  Write-CampaignRunnerJson -Value $lock -Path $lockPath
  return $lock
}

function Update-CampaignRunnerLockHeartbeat {
  param($Lock)
  if (-not $Lock) { return }
  $Lock.heartbeat_at = Get-CampaignRunnerNow
  $Lock.expires_at = (Get-Date).ToUniversalTime().AddMinutes([Math]::Max(1, $MaxRuntimeMinutes)).ToString("o")
  Write-CampaignRunnerJson -Value $Lock -Path (Get-CampaignRunnerLockPath -TargetCampaignId $Lock.campaign_id -TargetProjectId $Lock.project_id)
}

function Release-CampaignRunnerLock {
  param($Lock, [string]$Reason)
  if (-not $Lock) { return }
  $Lock.lock_status = "released"
  $Lock.release_reason = $Reason
  $Lock.heartbeat_at = Get-CampaignRunnerNow
  Write-CampaignRunnerJson -Value $Lock -Path (Get-CampaignRunnerLockPath -TargetCampaignId $Lock.campaign_id -TargetProjectId $Lock.project_id)
}

function Get-CampaignRunnerStepPlan {
  param($Snapshot, [int]$Index)
  $steps = @($Snapshot.steps | Sort-Object order)
  if ($Index -ge $steps.Count) { return $null }
  return $steps[$Index]
}

function Invoke-CampaignRunner {
  param([ValidateSet("run-next", "run-until-hold", "run-until-complete", "resume")] [string]$RunnerCommand)
  if ([string]::IsNullOrWhiteSpace($CampaignId) -and -not [string]::IsNullOrWhiteSpace($GoalPackDir)) {
    $script:CampaignId = (Read-JsonFile -Path (Get-GoalPackManifestPath)).campaign_id
  }
  $snapshot = Get-CampaignRunnerSnapshot
  $scope = Get-CampaignRunnerApprovalScope
  $state = Read-CampaignRunnerJson -Path (Get-CampaignRunnerStatePath -TargetCampaignId $snapshot.campaign.campaign_id)
  if (-not $state -or $RunnerCommand -ne "resume") { $state = New-CampaignRunnerState -Snapshot $snapshot }
  $state.operator_approval_scope = $scope
  $planned = New-Object System.Collections.Generic.List[object]
  $hardBlockers = New-Object System.Collections.Generic.List[string]
  $started = [datetime]::UtcNow
  $limitSteps = if ($RunnerCommand -eq "run-next") { 1 } else { [Math]::Max(1, $MaxSteps) }
  $lock = $null
  try {
    $lock = if ($effectiveDryRun) { Read-CampaignRunnerJson -Path (Get-CampaignRunnerLockPath -TargetCampaignId $snapshot.campaign.campaign_id -TargetProjectId $snapshot.campaign.project_id) } else { Acquire-CampaignRunnerLock -Snapshot $snapshot -State $state }
    $runnerLockStatus = Get-CampaignRunnerLockStatus -Lock $lock
    if ($runnerLockStatus -eq "active") { $hardBlockers.Add("active_runner_lock") | Out-Null }
    if ($runnerLockStatus -eq "stale") { $hardBlockers.Add("stale_runner_lock") | Out-Null }
    $hygiene = Get-CampaignRunnerHygiene
    if ($hygiene.active_tasks -gt 0) { $hardBlockers.Add("active_tasks_present") | Out-Null }
    if ($hygiene.stale_leases -gt 0) { $hardBlockers.Add("stale_leases_present") | Out-Null }
    if ($hygiene.stale_locks -gt 0) { $hardBlockers.Add("stale_locks_present") | Out-Null }
    if ($hygiene.stop_requested) { $hardBlockers.Add("operator_stop_requested") | Out-Null }
    if ((Get-GitMetadata).dirty -and -not ($GoalPackDir -or $ManifestFile)) { $hardBlockers.Add("worktree_dirty") | Out-Null }
    if ($AllowServerDeploy) { $hardBlockers.Add("allow_server_deploy_not_supported_by_campaign_runner") | Out-Null }
    if ($hardBlockers.Count -gt 0) {
      $state.runner_status = "held"
      $state.hold_reason = ($hardBlockers.ToArray() -join ",")
      Add-CampaignRunnerAudit -State $state -Decision "hold" -StepId $state.current_step_id -Reason $state.hold_reason
    } else {
      for ($i = [int]$state.steps_attempted; $i -lt @($snapshot.steps).Count; $i++) {
        if ($planned.Count -ge $limitSteps) { $state.runner_status = "held"; $state.hold_reason = "max_steps_reached"; break }
        if ($state.tasks_attempted -ge [Math]::Max(1, $MaxTasks)) { $state.runner_status = "held"; $state.hold_reason = "max_tasks_reached"; break }
        if ($MaxRuntimeMinutes -le 0 -or ([datetime]::UtcNow - $started).TotalMinutes -ge $MaxRuntimeMinutes) { $state.runner_status = "held"; $state.hold_reason = "max_runtime_reached"; break }
        $step = Get-CampaignRunnerStepPlan -Snapshot $snapshot -Index $i
        if (-not $step) { $state.runner_status = "completed"; $state.hold_reason = $null; break }
        $approval = Test-CampaignRunnerApproval -Step $step -Scope $scope
        $requiresHuman = [bool]$step.advance_gate.requires_human_approval
        $stepBlockers = @($approval.blockers)
        if ($requiresHuman -and -not $approval.ok) { $stepBlockers += "human_approval_required" }
        if ($StopOnFailure -and $step.status -eq "failed") { $stepBlockers += "failed_unrecovered_step" }
        $action = if ($stepBlockers.Count -gt 0) { "hold" } elseif ($effectiveDryRun) { "would_execute_step" } else { "execute_step" }
        $planned.Add([pscustomobject]@{
          step_id = $step.campaign_step_id
          goal_id = $step.goal_id
          title = $step.title
          order = $step.order
          action = $action
          approval = $approval
          blockers = @($stepBlockers)
          finalizer = [pscustomobject]@{
            wait_for_checks = $true
            rerun_transient_failures_once = $true
            allow_auto_merge = [bool]$AllowAutoMerge
            allow_evidence_repair = [bool]$AllowEvidenceRepair
          }
        }) | Out-Null
        $state.steps_attempted++
        $state.tasks_attempted++
        $state.current_step_id = $step.campaign_step_id
        if ($stepBlockers.Count -gt 0) {
          $state.runner_status = "held"
          $state.hold_reason = ($stepBlockers -join ",")
          Add-CampaignRunnerAudit -State $state -Decision "hold" -StepId $step.campaign_step_id -Reason $state.hold_reason
          break
        }
        Add-CampaignRunnerAudit -State $state -Decision $action -StepId $step.campaign_step_id -Reason "planned"
        if (-not $effectiveDryRun) {
          $execute = Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "execute-step", "-CampaignId", $snapshot.campaign.campaign_id, "-StepId", $step.campaign_step_id, "-ApiBase", $ApiBase, "-ProjectId", $snapshot.campaign.project_id, "-TokenFile", $TokenFile, "-Apply", "-Json")
          $taskId = @($execute.linked_task_ids)[0]
          if ($taskId -and $WorkerProfile) {
            Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-run-once.ps1", "-ApiBase", $ApiBase, "-ProjectId", $snapshot.campaign.project_id, "-TokenFile", $TokenFile, "-WorkerProfile", $WorkerProfile, "-TaskId", $taskId, "-NoSubmit", "-Apply", "-AllowDirty", "-Json") | Out-Null
          }
          if ($taskId -and ($AllowAutoMerge -or $AllowEvidenceRepair)) {
            Invoke-CampaignJsonScript -Arguments @("-File", ".\scripts\powershell\skybridge-pr-finalize.ps1", "-ApiBase", $ApiBase, "-ProjectId", $snapshot.campaign.project_id, "-TokenFile", $TokenFile, "-TaskId", $taskId, "-CampaignId", $snapshot.campaign.campaign_id, "-StepId", $step.campaign_step_id, "-AllowAutoMerge:$([bool]$AllowAutoMerge)", "-AllowEvidenceRepair:$([bool]$AllowEvidenceRepair)", "-Apply", "-Json") | Out-Null
          }
        }
        $state.steps_completed++
        $state.tasks_completed++
        Update-CampaignRunnerLockHeartbeat -Lock $lock
        if ($RunnerCommand -eq "run-next") { $state.runner_status = "idle"; $state.hold_reason = "run_next_completed"; break }
      }
      if ($planned.Count -eq @($snapshot.steps).Count -and -not $state.hold_reason -and $RunnerCommand -eq "run-until-complete") { $state.runner_status = "completed" }
      if (-not $state.runner_status -or $state.runner_status -eq "running") { $state.runner_status = "held"; $state.hold_reason = "runner_loop_stopped" }
    }
  } catch {
    $state.runner_status = "failed"
    $state.last_error = $_.Exception.Message
    Add-CampaignRunnerAudit -State $state -Decision "failed" -StepId $state.current_step_id -Reason $state.last_error
  } finally {
    $state.updated_at = Get-CampaignRunnerNow
    if ($state.runner_status -in @("held", "completed", "failed", "aborted", "idle")) { $state.stopped_at = $state.updated_at }
    Write-CampaignRunnerJson -Value $state -Path (Get-CampaignRunnerStatePath -TargetCampaignId $snapshot.campaign.campaign_id)
    if (-not $effectiveDryRun -and $lock) { Release-CampaignRunnerLock -Lock $lock -Reason $state.runner_status }
  }
  [pscustomobject]@{
    ok = ($state.runner_status -notin @("failed", "aborted"))
    command = $RunnerCommand
    mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
    project_id = $snapshot.campaign.project_id
    token_printed = $false
    campaign = $snapshot.campaign
    runner_state = $state
    runner_lock = $lock
    approval_scope = $scope
    planned_actions = @($planned.ToArray())
    hard_blockers = @($hardBlockers.ToArray())
    stop_reason = if ($state.hold_reason) { $state.hold_reason } else { $state.runner_status }
    safety = [pscustomobject]@{ dry_run_default = $true; mutations_require_apply = $true; deterministic_hard_veto_bypassed = $false; token_printed = $false }
  }
}

function Get-CampaignRunnerStatus {
  if ([string]::IsNullOrWhiteSpace($CampaignId) -and $GoalPackDir) { $script:CampaignId = (Read-JsonFile -Path (Get-GoalPackManifestPath)).campaign_id }
  $state = Read-CampaignRunnerJson -Path (Get-CampaignRunnerStatePath)
  $lock = Read-CampaignRunnerJson -Path (Get-CampaignRunnerLockPath)
  $snapshot = $null
  try { $snapshot = Get-CampaignRunnerSnapshot } catch {}
  [pscustomobject]@{
    ok = $true
    command = $Command
    mode = "read"
    project_id = $ProjectId
    token_printed = $false
    campaign = if ($snapshot) { $snapshot.campaign } else { $null }
    current_step_id = if ($snapshot) { $snapshot.campaign.current_step_id } elseif ($state) { $state.current_step_id } else { $null }
    runner_state = $state
    runner_lock = $lock
    runner_lock_status = Get-CampaignRunnerLockStatus -Lock $lock
    blockers = if ((Get-CampaignRunnerLockStatus -Lock $lock) -eq "stale") { @("stale_runner_lock") } else { @() }
  }
}

function Export-CampaignRunnerReport {
  $status = Get-CampaignRunnerStatus
  $markdown = @"
# Campaign Runner Report

- Campaign: $CampaignId
- Project: $ProjectId
- Runner status: $($status.runner_state.runner_status)
- Current step: $($status.current_step_id)
- Lock status: $($status.runner_lock_status)
- Stop reason: $($status.runner_state.hold_reason)
- Token printed: false

## Approval Scope

````json
$($status.runner_state.operator_approval_scope | ConvertTo-Json -Depth 20)
````

## Audit Log

````json
$($status.runner_state.audit_log | ConvertTo-Json -Depth 40)
````
"@
  $jsonReport = [pscustomobject]@{ ok = $true; token_printed = $false; status = $status; markdown = $markdown }
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($OutputFile -like "*.md") { $markdown | Set-Content -LiteralPath $OutputFile -Encoding UTF8 }
    else { $jsonReport | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8 }
  }
  [pscustomobject]@{
    ok = $true
    command = $Command
    mode = "read"
    project_id = $ProjectId
    token_printed = $false
    report = $jsonReport
  }
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
  "run-next" {
    $result = Invoke-CampaignRunner -RunnerCommand "run-next"
  }
  "run-until-hold" {
    $result = Invoke-CampaignRunner -RunnerCommand "run-until-hold"
  }
  "run-until-complete" {
    $result = Invoke-CampaignRunner -RunnerCommand "run-until-complete"
  }
  "runner-status" {
    $result = Get-CampaignRunnerStatus
  }
  "runner-report" {
    $result = Export-CampaignRunnerReport
  }
  "runner-stop" {
    $state = Read-CampaignRunnerJson -Path (Get-CampaignRunnerStatePath)
    if (-not $state) { $state = [pscustomobject]@{ runner_status = "idle"; campaign_id = $CampaignId; project_id = $ProjectId; audit_log = @() } }
    $state.runner_status = "aborted"
    $state.hold_reason = if ($Reason) { $Reason } else { "operator_stop" }
    $state.stopped_at = Get-CampaignRunnerNow
    $state.updated_at = $state.stopped_at
    Write-CampaignRunnerJson -Value $state -Path (Get-CampaignRunnerStatePath)
    $result = Get-CampaignRunnerStatus
  }
  "runner-hold" {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "runner-hold requires -Reason." }
    $state = Read-CampaignRunnerJson -Path (Get-CampaignRunnerStatePath)
    if (-not $state) { $state = [pscustomobject]@{ runner_status = "held"; campaign_id = $CampaignId; project_id = $ProjectId; audit_log = @() } }
    $state.runner_status = "held"
    $state.hold_reason = $Reason
    $state.stopped_at = Get-CampaignRunnerNow
    $state.updated_at = $state.stopped_at
    Write-CampaignRunnerJson -Value $state -Path (Get-CampaignRunnerStatePath)
    $result = Get-CampaignRunnerStatus
  }
  "runner-unlock" {
    $unlockReason = if ($RunnerUnlockReason) { $RunnerUnlockReason } else { $Reason }
    if ([string]::IsNullOrWhiteSpace($unlockReason)) { throw "runner-unlock requires -Reason or -RunnerUnlockReason." }
    $lockPath = Get-CampaignRunnerLockPath
    $lock = Read-CampaignRunnerJson -Path $lockPath
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; lock = $lock; would_unlock = $true; reason = $unlockReason }
    } else {
      if ($lock) {
        $lock.lock_status = "released"
        $lock.release_reason = $unlockReason
        $lock.heartbeat_at = Get-CampaignRunnerNow
        Write-CampaignRunnerJson -Value $lock -Path $lockPath
      }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; lock = $lock; unlocked = $true; reason = $unlockReason }
    }
  }
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
  "resume" {
    if ($GoalPackDir -or $ManifestFile -or $WorkerProfile -or $RunnerApprovalScope -or $AllowAutoMerge -or $AllowEvidenceRepair -or $HumanApproved -or $MaxSteps -gt 1 -or $MaxTasks -gt 1) {
      $result = Invoke-CampaignRunner -RunnerCommand "resume"
    } else {
      $targetStatusCommand = "resume"
    }
  }
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
  "execute-preview" {
    $result = New-CampaignExecutionPreview
  }
  "execute-step" {
    if ($Run) { throw "execute-step -Run is reserved for a future bounded runner integration; create the task first, then run the worker explicitly." }
    $preview = New-CampaignExecutionPreview
    if (@($preview.blockers).Count -gt 0) {
      $result = $preview
    } elseif ($effectiveDryRun) {
      $result = $preview
    } else {
      $created = Invoke-CampaignApi -Method POST -Path "/v1/tasks" -Body $preview.task
      $linkBody = @{
        linked_task_ids = @($created.task.task_id)
        evidence_summary = @{
          summary = "Campaign step execution task created: $($created.task.task_id). Worker execution is not started by execute-step."
          created_at = (Get-Date).ToUniversalTime().ToString("o")
          task_id = $created.task.task_id
          campaign_id = $preview.campaign_id
          campaign_step_id = $preview.step_id
          markdown_hash = $preview.markdown_hash
        }
      }
      $linked = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($preview.campaign_id))/steps/$([uri]::EscapeDataString($preview.step_id))/attach-evidence" -Body $linkBody
      $result = [pscustomobject]@{
        ok = $true
        command = $Command
        mode = "apply"
        project_id = $ProjectId
        token_printed = $false
        campaign_id = $preview.campaign_id
        step_id = $preview.step_id
        goal_id = $preview.goal_id
        task = $created.task
        campaign = $linked.campaign
        steps = @($linked.step)
        linked_task_ids = @($created.task.task_id)
        expected_files = @($preview.expected_files)
      }
    }
  }
  "link-task" {
    if ([string]::IsNullOrWhiteSpace($CampaignId) -or [string]::IsNullOrWhiteSpace($StepId) -or [string]::IsNullOrWhiteSpace($TaskId)) { throw "link-task requires -CampaignId, -StepId, and -TaskId." }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $StepId; task_id = $TaskId; would_link_task = $true }
    } else {
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($StepId))/attach-evidence" -Body @{
        linked_task_ids = @($TaskId)
        evidence_summary = @{ summary = "Campaign step linked to task $TaskId."; created_at = (Get-Date).ToUniversalTime().ToString("o"); task_id = $TaskId }
      }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step); linked_task_ids = @($TaskId) }
    }
  }
  "attach-execution-evidence" {
    if ([string]::IsNullOrWhiteSpace($CampaignId) -or [string]::IsNullOrWhiteSpace($StepId)) { throw "attach-execution-evidence requires -CampaignId and -StepId." }
    if (-not $EvidenceSummary -and $LinkedTaskIds.Count -eq 0 -and $LinkedPrUrls.Count -eq 0) { throw "attach-execution-evidence requires -EvidenceSummary, -LinkedTaskIds, or -LinkedPrUrls." }
    if ($effectiveDryRun) {
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; campaign_id = $CampaignId; step_id = $StepId; would_attach_execution_evidence = $true }
    } else {
      $body = @{ linked_task_ids = @($LinkedTaskIds); linked_pr_urls = @($LinkedPrUrls) }
      if ($EvidenceSummary) { $body.evidence_summary = @{ summary = $EvidenceSummary; created_at = (Get-Date).ToUniversalTime().ToString("o"); linked_task_ids = @($LinkedTaskIds); linked_pr_urls = @($LinkedPrUrls) } }
      $payload = Invoke-CampaignApi -Method POST -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))/steps/$([uri]::EscapeDataString($StepId))/attach-evidence" -Body $body
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($payload.step) }
    }
  }
  "step-report" {
    if ([string]::IsNullOrWhiteSpace($CampaignId)) { throw "step-report requires -CampaignId." }
    $payload = Invoke-CampaignApi -Method GET -Path "/v1/campaigns/$([uri]::EscapeDataString($CampaignId))"
    $step = if ($StepId) { @($payload.steps | Where-Object { $_.campaign_step_id -eq $StepId })[0] } elseif ($GoalId) { @($payload.steps | Where-Object { $_.goal_id -eq $GoalId })[0] } else { @($payload.steps | Where-Object { $_.campaign_step_id -eq $payload.campaign.current_step_id })[0] }
    if (-not $step) { throw "Campaign step not found for report." }
    $tasks = @()
    foreach ($linkedTaskId in @($step.linked_task_ids)) {
      try { $tasks += (Invoke-CampaignApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString([string]$linkedTaskId))").task } catch {}
    }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; campaign = $payload.campaign; steps = @($step); linked_tasks = @($tasks) }
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
