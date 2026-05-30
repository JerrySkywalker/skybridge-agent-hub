[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("init", "validate-pack", "import", "list", "show", "steps", "status", "start", "pause", "hold", "resume", "advance-preview", "advance", "complete-step", "fail-step", "attach-evidence", "export-report")]
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
    "Gate:         $($Result.gate.decision)"
    "Reason:       $($Result.gate.reason)"
    if ($Result.gate.blockers) { "Blockers:     $(@($Result.gate.blockers) -join ', ')" }
    if ($Result.gate.warnings) { "Warnings:     $(@($Result.gate.warnings) -join ', ')" }
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
