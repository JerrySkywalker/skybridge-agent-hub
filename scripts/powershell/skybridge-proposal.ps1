[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("list", "show", "review", "approve", "accept", "reject", "defer", "supersede", "convert")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [string]$PlanningSessionId,
  [string]$ProposalId,
  [string]$TaskId,
  [string[]]$Status = @(),
  [string[]]$ReviewStatus = @(),
  [string]$Risk,
  [string]$TaskType,
  [string[]]$PolicyDecision = @(),
  [int]$Limit = 20,
  [switch]$ShowAll,
  [string]$Reason,
  [string]$SupersededBy,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$AllowHighRisk,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-ProposalApiConfig {
  $authMode = "none"
  if ($TokenEnvVar -or $TokenFile) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Invoke-ProposalApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 20
}

function Get-ProposalReviewStatus {
  param($Proposal)
  if ($Proposal.review_status) { return [string]$Proposal.review_status }
  if ($Proposal.status) { return [string]$Proposal.status }
  return "proposed"
}

function Get-ProposalDependencies {
  param($Proposal)
  return @(@($Proposal.dependencies) + @($Proposal.depends_on) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Select-ProposalView {
  param($Proposal)
  [pscustomobject]@{
    proposal_id = $Proposal.proposal_id
    status = $Proposal.status
    review_status = Get-ProposalReviewStatus -Proposal $Proposal
    policy_decision = $Proposal.policy_decision
    risk = $Proposal.risk
    task_type = $Proposal.task_type
    title = $Proposal.title
    expected_files = @($Proposal.expected_files)
    required_capabilities = @($Proposal.required_capabilities)
    original_required_capabilities = @($Proposal.original_required_capabilities)
    normalized_required_capabilities = @($Proposal.normalized_required_capabilities)
    rationale = $Proposal.rationale
    dependencies = @(Get-ProposalDependencies -Proposal $Proposal)
    converted_task_id = $Proposal.converted_task_id
    review_reason = $Proposal.review_reason
    reviewed_by = $Proposal.reviewed_by
    reviewed_at = $Proposal.reviewed_at
    approved_by = $Proposal.approved_by
    approved_at = $Proposal.approved_at
    superseded_by = $Proposal.superseded_by
  }
}

function Test-ProposalApprovalPolicy {
  param($Proposal, [array]$AllProposals, [switch]$AllowHighRisk)
  $reasons = New-Object System.Collections.Generic.List[string]
  $decision = "accepted_for_execution"
  $taskType = [string]$Proposal.task_type
  $risk = [string]$Proposal.risk
  $files = @($Proposal.expected_files | ForEach-Object { ([string]$_).Replace("\", "/") })
  $capsSource = if ($Proposal.PSObject.Properties["normalized_required_capabilities"] -and @($Proposal.normalized_required_capabilities).Count -gt 0) { $Proposal.normalized_required_capabilities } else { $Proposal.required_capabilities }
  $caps = @($capsSource | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })

  if ($Proposal.status -in @("rejected", "deferred", "superseded", "blocked_dependency", "converted", "executed")) {
    $decision = "ask_human"; $reasons.Add("proposal status $($Proposal.status) is not approvable") | Out-Null
  }
  if ($risk -ne "low" -and -not $AllowHighRisk) {
    $decision = "rejected_high_risk"; $reasons.Add("risk must be low") | Out-Null
  }
  if ($taskType -in @("deploy", "production", "secret", "secrets", "github-settings", "branch-protection", "server-config", "server-root-config")) {
    $decision = "rejected_high_risk"; $reasons.Add("task_type is blocked") | Out-Null
  } elseif ($taskType -notin @("docs", "local-smoke")) {
    $decision = "ask_human"; $reasons.Add("task_type must be docs or local-smoke") | Out-Null
  }
  if ($caps -notcontains "codex") {
    $decision = "ask_human"; $reasons.Add("normalized capabilities must include codex") | Out-Null
  }
  if (@($Proposal.acceptance_criteria).Count -eq 0 -or @($Proposal.evidence_requirements).Count -eq 0) {
    $decision = "ask_human"; $reasons.Add("acceptance_criteria and evidence_requirements are required") | Out-Null
  }
  foreach ($file in $files) {
    $docsOk = $taskType -eq "docs" -and $file -like "docs/*"
    $smokeOk = $taskType -eq "local-smoke" -and $file -like "scripts/powershell/smoke-*.ps1"
    if (-not ($docsOk -or $smokeOk) -or $file -like ".agent/*" -or $file -like ".data/*" -or $file -like ".env*" -or $file -like "deploy/*") {
      $decision = "rejected_expected_files"; $reasons.Add("expected file is outside allowed $taskType paths: $file") | Out-Null
    }
  }
  $blockedText = (@($Proposal.title, $Proposal.body, $Proposal.prompt_summary, $Proposal.rationale, @($Proposal.expected_files)) -join " ")
  if ($blockedText -match "(?i)(production deploy|production|deploy|docker daemon|branch protection|github settings|server config|server-root-config|/opt/skybridge-agent-hub|commit \.env|token file|private key|secret)") {
    $decision = "rejected_high_risk"; $reasons.Add("proposal mentions a blocked high-risk surface") | Out-Null
  }
  $dependencies = @(Get-ProposalDependencies -Proposal $Proposal)
  foreach ($dependencyId in $dependencies) {
    if ([string]::IsNullOrWhiteSpace([string]$dependencyId)) { continue }
    $dependency = @($AllProposals | Where-Object { $_.proposal_id -eq $dependencyId } | Select-Object -First 1)
    if (@($dependency).Count -eq 0 -or @($dependency)[0].status -notin @("converted", "executed")) {
      $decision = "dependency_blocked"; $reasons.Add("dependency is not converted or executed: $dependencyId") | Out-Null
    }
  }
  [pscustomobject]@{ decision = $decision; reasons = @($reasons.ToArray()) }
}

function Write-ProposalResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 60 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.proposal) {
    $proposal = $Result.proposal
    "Proposal:     $($proposal.proposal_id)"
    "Status:       $($proposal.status)"
    "Review:      $($proposal.review_status)"
    "Policy:      $($proposal.policy_decision)"
    "Risk:        $($proposal.risk)"
    "Type:        $($proposal.task_type)"
    "Title:       $($proposal.title)"
    "Files:       $(@($proposal.expected_files) -join ', ')"
    "Caps:        $(@($proposal.required_capabilities) -join ', ')"
    "NormCaps:    $(@($proposal.normalized_required_capabilities) -join ', ')"
    "Deps:        $(@($proposal.dependencies) -join ', ')"
    if ($proposal.review_reason) { "Reason:      $($proposal.review_reason)" }
    if ($proposal.rationale) { "Rationale:   $($proposal.rationale)" }
  }
  if ($Result.task) { "Task:         $($Result.task.task_id)" }
  if ($Result.proposals) {
    "Proposals:    $(@($Result.proposals).Count)"
    foreach ($proposal in @($Result.proposals)) {
      "  $($proposal.proposal_id) [$($proposal.review_status)] $($proposal.policy_decision) $($proposal.risk) $($proposal.task_type) $($proposal.title)"
    }
  }
  if ($Result.validation) { "Validation:   $($Result.validation.decision) $(@($Result.validation.reasons) -join '; ')" }
  "TokenPrinted: false"
}

$script:Config = New-ProposalApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

if ($Limit -lt 1) { $Limit = 20 }
$effectiveDryRun = $DryRun -or -not $Apply
$commandName = if ($Command -eq "accept") { "approve" } else { $Command }
$result = $null

function Get-ProjectProposals {
  $path = "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))"
  if ($MasterGoalId) { $path += "&master_goal_id=$([uri]::EscapeDataString($MasterGoalId))" }
  $payload = Invoke-ProposalApi -Method GET -Path $path
  $items = @($payload.proposals)
  if ($PlanningSessionId) { $items = @($items | Where-Object { $_.planning_session_id -eq $PlanningSessionId }) }
  if ($Status.Count -gt 0) {
    $wanted = @($Status | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $items = @($items | Where-Object { $wanted -contains ([string]$_.status).ToLowerInvariant() })
  }
  if ($ReviewStatus.Count -gt 0) {
    $wantedReview = @($ReviewStatus | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $items = @($items | Where-Object { $wantedReview -contains (Get-ProposalReviewStatus -Proposal $_).ToLowerInvariant() })
  }
  if ($Risk) { $items = @($items | Where-Object { $_.risk -eq $Risk }) }
  if ($TaskType) { $items = @($items | Where-Object { $_.task_type -eq $TaskType }) }
  if ($PolicyDecision.Count -gt 0) {
    $wantedPolicy = @($PolicyDecision | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $items = @($items | Where-Object { $wantedPolicy -contains ([string]$_.policy_decision).ToLowerInvariant() })
  }
  if (-not $ShowAll) { $items = @($items | Select-Object -First $Limit) }
  return @($items)
}

switch ($commandName) {
  "list" {
    $proposals = @(Get-ProjectProposals | ForEach-Object { Select-ProposalView -Proposal $_ })
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = "read"; project_id = $ProjectId; token_printed = $false; proposals = $proposals }
  }
  "show" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal show requires -ProposalId." }
    $payload = Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))"
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = "read"; project_id = $ProjectId; token_printed = $false; proposal = (Select-ProposalView -Proposal $payload.proposal) }
  }
  "review" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal review requires -ProposalId." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($effectiveDryRun) {
      $proposal = Select-ProposalView -Proposal $current
      $proposal.review_status = "would_review"
    } else {
      $body = @{ status = "reviewed"; review_status = "reviewed"; reviewed_by = "operator"; review_reason = $Reason }
      $proposal = Select-ProposalView -Proposal ((Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body $body).proposal)
    }
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "approve" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal approve requires -ProposalId." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    $allProposals = @((Invoke-ProposalApi -Method GET -Path "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))").proposals)
    $policy = Test-ProposalApprovalPolicy -Proposal $current -AllProposals $allProposals -AllowHighRisk:$AllowHighRisk
    if ($policy.decision -notin @("accepted_for_execution", "accepted_for_preview", "ask_human")) {
      throw "Proposal $ProposalId failed approval policy: $($policy.decision) ($(@($policy.reasons) -join '; '))."
    }
    if ($effectiveDryRun) {
      $proposal = Select-ProposalView -Proposal $current
      $proposal.review_status = "would_approve"
    } else {
      $body = @{ status = "approved"; review_status = "approved"; reviewed_by = "operator"; approved_by = "operator"; review_reason = $Reason; policy_decision = $policy.decision }
      $proposal = Select-ProposalView -Proposal ((Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body $body).proposal)
    }
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; validation = $policy; proposal = $proposal }
  }
  "reject" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal reject requires -ProposalId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "proposal reject requires -Reason." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($effectiveDryRun) {
      $proposal = Select-ProposalView -Proposal $current
      $proposal.review_status = "would_reject"
      $proposal.review_reason = $Reason
    } else {
      $body = @{ status = "rejected"; review_status = "rejected"; reviewed_by = "operator"; review_reason = $Reason }
      $proposal = Select-ProposalView -Proposal ((Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body $body).proposal)
    }
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "defer" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal defer requires -ProposalId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "proposal defer requires -Reason." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($effectiveDryRun) {
      $proposal = Select-ProposalView -Proposal $current
      $proposal.review_status = "would_defer"
      $proposal.review_reason = $Reason
    } else {
      $body = @{ status = "deferred"; review_status = "deferred"; reviewed_by = "operator"; review_reason = $Reason }
      $proposal = Select-ProposalView -Proposal ((Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body $body).proposal)
    }
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "supersede" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal supersede requires -ProposalId." }
    if ([string]::IsNullOrWhiteSpace($SupersededBy)) { throw "proposal supersede requires -SupersededBy." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($effectiveDryRun) {
      $proposal = Select-ProposalView -Proposal $current
      $proposal.review_status = "would_supersede"
      $proposal.superseded_by = $SupersededBy
    } else {
      $body = @{ status = "superseded"; review_status = "superseded"; reviewed_by = "operator"; review_reason = $Reason; superseded_by = $SupersededBy }
      $proposal = Select-ProposalView -Proposal ((Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body $body).proposal)
    }
    $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "convert" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal convert requires -ProposalId." }
    $proposal = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($proposal.status -ne "approved") { throw "Proposal $ProposalId must be approved before conversion." }
    $allProposals = @((Invoke-ProposalApi -Method GET -Path "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))").proposals)
    $policy = Test-ProposalApprovalPolicy -Proposal $proposal -AllProposals $allProposals -AllowHighRisk:$AllowHighRisk
    if ($policy.decision -notin @("accepted_for_execution", "accepted_for_preview", "ask_human")) {
      throw "Proposal $ProposalId failed conversion policy: $($policy.decision) ($(@($policy.reasons) -join '; '))."
    }
    if ($effectiveDryRun) {
      $taskCapabilities = if ($proposal.PSObject.Properties["normalized_required_capabilities"] -and @($proposal.normalized_required_capabilities).Count -gt 0) { @($proposal.normalized_required_capabilities) } else { @($proposal.required_capabilities) }
      $task = [pscustomobject]@{
        task_id = if ($TaskId) { $TaskId } else { "task_$ProposalId" }
        project_id = $proposal.project_id
        title = $proposal.title
        risk = $proposal.risk
        source = "planner"
        task_type = $proposal.task_type
        allowed_paths = @($proposal.expected_files)
        validation = @($proposal.evidence_requirements)
        required_capabilities = @($taskCapabilities)
      }
      $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; validation = $policy; proposal = (Select-ProposalView -Proposal $proposal); task = $task }
    } else {
      $body = @{}
      if ($TaskId) { $body.task_id = $TaskId }
      $payload = Invoke-ProposalApi -Method POST -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))/convert" -Body $body
      $result = [pscustomobject]@{ ok = $true; command = $commandName; mode = "apply"; project_id = $ProjectId; token_printed = $false; validation = $policy; proposal = (Select-ProposalView -Proposal $payload.proposal); task = $payload.task }
    }
  }
}

Write-ProposalResult -Result $result
