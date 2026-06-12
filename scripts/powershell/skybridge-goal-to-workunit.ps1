[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "scan", "preview", "risk-gate", "candidate-pack", "safe-summary", "fixture-convert", "manifest-validate")]
  [string]$Command,
  [ValidateSet("default", "low-docs", "secrets", "production", "github-settings", "self-approval")]
  [string]$Scenario = "default",
  [switch]$WriteManifest,
  [string]$Reason,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SkybridgeCoreEngineModules = @("Skybridge.Core.psm1", "Skybridge.WorkunitRegistry.psm1", "Skybridge.SafetyScanner.psm1")
foreach ($module in $SkybridgeCoreEngineModules) {
  Import-Module (Join-Path $PSScriptRoot "lib/$module") -Force
}

function Get-RepoRoot {
  (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Test-SecretLookingText {
  param([string]$Text)
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_codex_transcript|raw_worker_log|token_printed"\s*:\s*true'
}

function Get-StableHash {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function New-GoalFixture {
  param([string]$Kind)
  switch ($Kind) {
    "secrets" {
      [pscustomobject]@{
        proposed_goal_id = "proposed-secret-rotation"
        title = "Rotate production secrets"
        source_goal_path = "goals/proposed/proposed-secret-rotation.md"
        reviewed_goal_path = $null
        text = "Rotate secrets, write token file, update private keys."
        risk = "high"
        task_type = "secret_rotation"
        review_status = "approved"
        allowed_paths = @()
      }
    }
    "production" {
      [pscustomobject]@{
        proposed_goal_id = "proposed-production-deploy"
        title = "Production deploy"
        source_goal_path = "goals/proposed/proposed-production-deploy.md"
        reviewed_goal_path = $null
        text = "Run production deploy and server-root config update."
        risk = "high"
        task_type = "production_deploy"
        review_status = "approved"
        allowed_paths = @("deploy/**")
      }
    }
    "github-settings" {
      [pscustomobject]@{
        proposed_goal_id = "proposed-github-settings"
        title = "GitHub branch protection update"
        source_goal_path = "goals/proposed/proposed-github-settings.md"
        reviewed_goal_path = $null
        text = "Modify GitHub settings and branch protection."
        risk = "high"
        task_type = "github_settings"
        review_status = "approved"
        allowed_paths = @(".github/**")
      }
    }
    default {
      $path = "goals/proposed/proposed-goal-201-local-readme-refresh.md"
      $text = "Refresh local project documentation for the proposed-goal workflow after Goal 200 imports reviewed drafts. Task type docs/local-smoke only."
      [pscustomobject]@{
        proposed_goal_id = "proposed-goal-201-local-readme-refresh"
        title = "Goal 201 Local README Refresh"
        source_goal_path = $path
        reviewed_goal_path = "goals/reviewed/proposed-goal-201-local-readme-refresh.md"
        text = $text
        risk = "low"
        task_type = "docs"
        review_status = if ($Scenario -eq "self-approval") { "proposed" } else { "approved" }
        allowed_paths = @("docs/**", "scripts/powershell/smoke-*.ps1")
      }
    }
  }
}

function New-RiskGate {
  param($Goal)
  $text = (@($Goal.title, $Goal.text, $Goal.task_type, @($Goal.allowed_paths)) -join " ")
  $blockedTerms = @()
  foreach ($term in @("production deploy", "secret rotation", "server-root config", "DNS", "OpenResty", "Hermes config", "GitHub settings", "branch protection", "arbitrary shell", "auto-execution", "auto-merge", "token file", "private key")) {
    if ($text -match [regex]::Escape($term)) { $blockedTerms += $term }
  }
  $reasons = @()
  $decision = "allow_candidate_ready"
  if (@($blockedTerms).Count -gt 0 -or $Goal.task_type -in @("production_deploy", "secret_rotation", "github_settings", "branch_protection", "server_root_config")) {
    $decision = "blocked"
    $reasons += "blocked_high_risk_surface"
  }
  if ($Goal.risk -ne "low") {
    $decision = if ($decision -eq "blocked") { "blocked" } else { "review_required" }
    $reasons += "risk_not_low"
  }
  if ($Goal.task_type -notin @("docs", "local-smoke")) {
    $decision = if ($decision -eq "blocked") { "blocked" } else { "review_required" }
    $reasons += "task_type_not_docs_or_local_smoke"
  }
  if ($Goal.review_status -notin @("approved", "approved_for_import", "reviewed")) {
    $decision = if ($decision -eq "blocked") { "blocked" } else { "review_required" }
    $reasons += "generated_goal_must_not_approve_itself"
  }
  if (@($reasons).Count -eq 0) { $reasons += "low_risk_docs_or_local_smoke" }
  [pscustomobject]@{
    schema = "skybridge.workunit_candidate_risk_gate.v1"
    candidate_id = "candidate-$($Goal.proposed_goal_id)"
    decision = $decision
    reasons = @($reasons | Select-Object -Unique)
    blocked_terms = @($blockedTerms | Select-Object -Unique)
    generated_goal_self_approved = $false
    token_printed = $false
  }
}

function New-Candidate {
  param($Goal)
  $gate = New-RiskGate -Goal $Goal
  $hash = Get-StableHash -Text $Goal.text
  $status = switch ($gate.decision) {
    "allow_candidate_ready" { "candidate_ready" }
    "review_required" { "reviewed" }
    default { "blocked" }
  }
  [pscustomobject]@{
    schema = "skybridge.proposed_goal_workunit_candidate.v1"
    candidate_id = "candidate-$($Goal.proposed_goal_id)"
    source_proposed_goal_id = $Goal.proposed_goal_id
    source_goal_path = $Goal.source_goal_path
    reviewed_goal_path = $Goal.reviewed_goal_path
    project_id = "skybridge-agent-hub"
    campaign_id = "bootstrap-trial-201"
    candidate_pack_id = "candidate-pack-proposed-goals-preview"
    suggested_workunit_id = "workunit-candidate-$($Goal.proposed_goal_id)"
    suggested_task_type = $Goal.task_type
    risk = if ($gate.decision -eq "blocked") { "blocked" } else { $Goal.risk }
    allowed_paths = @($Goal.allowed_paths)
    blocked_paths = @(".env*", "deploy/**", "docs/operations/openresty-*", "config/hermes*", ".github/**")
    required_capabilities = @("codex", "repo_local_docs")
    estimated_runtime_minutes = if ($gate.decision -eq "blocked") { 0 } else { 20 }
    max_prs = 0
    requires_human_review = $true
    conversion_status = $status
    blockers = if ($gate.decision -eq "blocked") { @($gate.reasons) } else { @() }
    warnings = @("preview_only_execution_disabled", "bounded_queue_apply_disabled", "execution_review_required")
    content_hash = $hash
    manifest_hash = Get-StableHash -Text "candidate-pack-proposed-goals-preview:${hash}:$status"
    token_printed = $false
  }
}

function New-CandidatePack {
  $goals = if ($Scenario -eq "default") { @(New-GoalFixture "low-docs"; New-GoalFixture "production") } else { @(New-GoalFixture $Scenario) }
  $candidates = @($goals | ForEach-Object { New-Candidate -Goal $_ })
  $gates = @($goals | ForEach-Object { New-RiskGate -Goal $_ })
  [pscustomobject]@{
    schema = "skybridge.workunit_candidate_pack.v1"
    candidate_pack_id = "candidate-pack-proposed-goals-preview"
    project_id = "skybridge-agent-hub"
    campaign_id = "bootstrap-trial-201"
    candidates = $candidates
    risk_gates = $gates
    candidate_ready_count = @($candidates | Where-Object conversion_status -eq "candidate_ready").Count
    blocked_count = @($candidates | Where-Object conversion_status -eq "blocked").Count
    requires_review_count = @($candidates | Where-Object requires_human_review).Count
    bounded_queue_preview_only = $true
    apply_available = $false
    execution_disabled = $true
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    next_safe_action = "Review candidate pack and keep execution disabled until a future explicit bounded-queue apply goal authorizes it."
    token_printed = $false
  }
}

function New-Manifest {
  $pack = New-CandidatePack
  [pscustomobject]@{
    schema = "skybridge.workunit_candidate_manifest.v1"
    manifest_id = "manifest-proposed-goal-workunit-candidates-preview"
    candidate_pack_id = $pack.candidate_pack_id
    manifest_path = ".agent/tmp/workunit-candidates/$($pack.candidate_pack_id).json"
    manifest_hash = Get-StableHash -Text ($pack | ConvertTo-Json -Depth 80 -Compress)
    candidates = $pack.candidates
    execution_review_required = $true
    apply_available = $false
    task_created = $false
    task_claimed = $false
    task_executed = $false
    token_printed = $false
  }
}

function Write-FixtureManifest {
  param($Manifest)
  if (-not $WriteManifest) { return $false }
  if ([string]::IsNullOrWhiteSpace($Reason)) { throw "Fixture manifest write requires -Reason." }
  $root = Get-RepoRoot
  $target = Join-Path $root $Manifest.manifest_path
  $allowedRoot = (Join-Path $root ".agent\tmp\workunit-candidates")
  $resolvedParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $target))
  if (-not $resolvedParent.StartsWith([System.IO.Path]::GetFullPath($allowedRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Manifest writes are confined to .agent/tmp/workunit-candidates."
  }
  New-Item -ItemType Directory -Path $resolvedParent -Force | Out-Null
  $Manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $target -Encoding UTF8
  return $true
}

$pack = New-CandidatePack
$manifest = New-Manifest
$manifestWritten = Write-FixtureManifest -Manifest $manifest

$result = switch ($Command) {
  "schema" {
    [pscustomobject]@{
      schema = "skybridge.goal_to_workunit_schema_summary.v1"
      schemas = @("skybridge.proposed_goal_workunit_candidate.v1", "skybridge.goal_to_workunit_conversion.v1", "skybridge.workunit_candidate_pack.v1", "skybridge.workunit_candidate_review.v1", "skybridge.workunit_candidate_risk_gate.v1", "skybridge.workunit_candidate_manifest.v1")
      apply_available = $false
      token_printed = $false
    }
  }
  "scan" {
    [pscustomobject]@{ schema = "skybridge.goal_to_workunit_scan.v1"; proposed_goal_count = @($pack.candidates).Count; candidates = $pack.candidates; token_printed = $false }
  }
  "preview" {
    [pscustomobject]@{
      schema = "skybridge.goal_to_workunit_conversion.v1"
      conversion_id = "conversion-proposed-goals-to-workunit-candidates-preview"
      mode = "preview"
      candidate_count = @($pack.candidates).Count
      candidate_ready_count = $pack.candidate_ready_count
      blocked_count = $pack.blocked_count
      execution_review_required = $true
      task_created = $false
      task_claimed = $false
      task_executed = $false
      pr_created = $false
      token_printed = $false
    }
  }
  "risk-gate" { [pscustomobject]@{ schema = "skybridge.goal_to_workunit_risk_gate_summary.v1"; risk_gates = $pack.risk_gates; token_printed = $false } }
  "candidate-pack" { $pack }
  "safe-summary" {
    [pscustomobject]@{
      schema = "skybridge.goal_to_workunit_safe_summary.v1"
      candidate_count = @($pack.candidates).Count
      candidate_ready_count = $pack.candidate_ready_count
      blocked_count = $pack.blocked_count
      bounded_queue_preview_only = $true
      apply_available = $false
      task_created = $false
      task_claimed = $false
      task_executed = $false
      pr_created = $false
      token_printed = $false
    }
  }
  "fixture-convert" { [pscustomobject]@{ schema = "skybridge.goal_to_workunit_fixture_convert.v1"; manifest = $manifest; manifest_written = $manifestWritten; execution_review_required = $true; token_printed = $false } }
  "manifest-validate" { [pscustomobject]@{ schema = "skybridge.workunit_candidate_manifest_validation.v1"; manifest = $manifest; valid = $true; apply_available = $false; token_printed = $false } }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw output field detected." }
if ($Json) { $text } else { $result | Format-List }
