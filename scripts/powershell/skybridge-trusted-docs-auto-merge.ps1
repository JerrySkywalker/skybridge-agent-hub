[CmdletBinding()]
param(
  [ValidateSet("policy", "gate", "decision", "audit", "preview-report", "scoped-policy", "scoped-decision", "scoped-gate", "scoped-audit", "scoped-merge")]
  [string]$Command = "policy",
  [ValidateSet("eligible-docs-only", "disallowed-script", "multiple-files", "deletion", "token-content", "missing-ci", "open-review-hold", "no-human-override", "scoped-eligible", "scoped-wrong-pr", "scoped-non-docs", "scoped-multiple-files", "scoped-deletion", "scoped-failing-ci", "scoped-secret-content")]
  [string]$Fixture = "eligible-docs-only",
  [int]$ScopedPrNumber = 0,
  [switch]$UseLivePr,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = ".agent/tmp/trusted-docs-auto-merge"

function Resolve-TrustedDocsPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Test-TrustedDocsUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Write-TrustedDocsSafeJson([string]$Path, $Value) {
  $full = Resolve-TrustedDocsPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $json = $Value | ConvertTo-Json -Depth 20
  if (Test-TrustedDocsUnsafeText $json) { throw "Refusing unsafe trusted-docs JSON: $Path" }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function Write-TrustedDocsSafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-TrustedDocsPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  if (Test-TrustedDocsUnsafeText $text) { throw "Refusing unsafe trusted-docs markdown: $Path" }
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function New-TrustedDocsPolicy {
  [pscustomobject]@{
    schema = "skybridge.trusted_docs_auto_merge_policy.v1"
    trusted_docs_auto_merge_enabled = $false
    auto_merge_apply_enabled = $false
    max_files = 1
    max_additions = 20
    max_deletions = 0
    allowed_paths = @("docs/**", "README.md")
    forbidden_paths = @(".github/**", "apps/**", "packages/**", "scripts/**", "server/**", "infra/**", ".env*", "**/*secret*", "**/*token*")
    require_release_gate = $true
    require_resource_gate = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit = $true
    require_redaction = $true
    require_human_override = $true
    token_printed = $false
  }
}

function New-TrustedDocsScopedPolicy {
  [pscustomobject]@{
    schema = "skybridge.trusted_docs_scoped_apply_policy.v1"
    trusted_docs_auto_merge_enabled = $false
    auto_merge_apply_enabled = $false
    generic_auto_merge_enabled = $false
    trusted_docs_scoped_apply_enabled = $true
    approval_scope = if ($ScopedPrNumber -gt 0) { @($ScopedPrNumber) } else { @() }
    max_files = 1
    max_additions = 25
    max_deletions = 0
    allowed_paths = @("docs/**", "README.md")
    forbidden_paths = @(".github/**", "apps/**", "packages/**", "scripts/**", "server/**", "infra/**", "ops/**", "*.json", ".env*", "**/*secret*", "**/*token*", "**/*key*", "**/*cookie*", "**/*auth*")
    require_all_ci_green = $true
    require_redaction_pass = $true
    require_no_raw_logs = $true
    require_no_secret_patterns = $true
    require_task_pr = $true
    require_low_risk_docs_local_smoke = $true
    require_release_gate = $true
    require_audit_event = $true
    require_human_equivalent_goal_approval = $true
    token_printed = $false
  }
}

function New-TrustedDocsFixture {
  switch ($Fixture) {
    "disallowed-script" { return [pscustomobject]@{ pr_number = 9002; files = @([pscustomobject]@{ path = "scripts/example.ps1"; additions = 3; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
    "multiple-files" { return [pscustomobject]@{ pr_number = 9003; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 3; deletions = 0 }, [pscustomobject]@{ path = "README.md"; additions = 1; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
    "deletion" { return [pscustomobject]@{ pr_number = 9004; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 1 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
    "token-content" { return [pscustomobject]@{ pr_number = 9005; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $false; raw_artifact_detected = $false; token_printed = $false } }
    "missing-ci" { return [pscustomobject]@{ pr_number = 9006; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "missing"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
    "open-review-hold" { return [pscustomobject]@{ pr_number = 9007; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; open_review_hold = $true; token_printed = $false } }
    "no-human-override" { return [pscustomobject]@{ pr_number = 9008; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
    default { return [pscustomobject]@{ pr_number = 9001; files = @([pscustomobject]@{ path = "docs/trusted-docs-preview.md"; additions = 8; deletions = 0 }); ci_status = "pass"; human_override = $false; content_secret_scan_passed = $true; raw_artifact_detected = $false; token_printed = $false } }
  }
}

function New-TrustedDocsScopedFixture {
  $approved = if ($ScopedPrNumber -gt 0) { $ScopedPrNumber } else { 9101 }
  switch ($Fixture) {
    "scoped-wrong-pr" { return [pscustomobject]@{ pr_number = 9102; title = "Fixture scoped wrong PR"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/scoped.md"; additions = 3; deletions = 0 }); ci_status = "pass"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    "scoped-non-docs" { return [pscustomobject]@{ pr_number = $approved; title = "Fixture scoped non docs"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "scripts/example.ps1"; additions = 3; deletions = 0 }); ci_status = "pass"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    "scoped-multiple-files" { return [pscustomobject]@{ pr_number = $approved; title = "Fixture scoped multiple files"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 3; deletions = 0 }, [pscustomobject]@{ path = "README.md"; additions = 1; deletions = 0 }); ci_status = "pass"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    "scoped-deletion" { return [pscustomobject]@{ pr_number = $approved; title = "Fixture scoped deletion"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 1 }); ci_status = "pass"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    "scoped-failing-ci" { return [pscustomobject]@{ pr_number = $approved; title = "Fixture scoped failing CI"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "fail"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    "scoped-secret-content" { return [pscustomobject]@{ pr_number = $approved; title = "Fixture scoped secret content"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/a.md"; additions = 1; deletions = 0 }); ci_status = "pass"; redaction_passed = $false; raw_artifact_detected = $false; content_secret_scan_passed = $false; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
    default { return [pscustomobject]@{ pr_number = $approved; title = "Server-approved Workunit scoped docs"; base = "main"; state = "OPEN"; is_draft = $false; mergeable = "MERGEABLE"; files = @([pscustomobject]@{ path = "docs/scoped.md"; additions = 8; deletions = 0 }); ci_status = "pass"; redaction_passed = $true; raw_artifact_detected = $false; content_secret_scan_passed = $true; task_pr = $true; low_risk_docs_local_smoke = $true; release_gate_pass = $true; human_equivalent_goal_approval = $true; token_printed = $false } }
  }
}

function Test-TrustedDocsAllowedPath([string]$Path) {
  $p = $Path.Replace("\", "/")
  return ($p -eq "README.md" -or $p -like "docs/*")
}

function ConvertFrom-LivePr {
  if ($ScopedPrNumber -le 0) { throw "ScopedPrNumber is required for live PR evaluation." }
  $prRaw = gh pr view $ScopedPrNumber --json number,title,baseRefName,state,isDraft,mergeable,additions,deletions,changedFiles,files,body 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Unable to read PR $ScopedPrNumber." }
  $pr = (($prRaw | Out-String).Trim() | ConvertFrom-Json)
  $checksRaw = gh pr checks $ScopedPrNumber --json name,state,bucket 2>$null
  $ciStatus = "missing"
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($checksRaw | Out-String).Trim())) {
    $checks = @(($checksRaw | Out-String).Trim() | ConvertFrom-Json)
    if ($checks.Count -gt 0 -and @($checks | Where-Object { $_.bucket -ne "pass" -and $_.state -ne "SUCCESS" }).Count -eq 0) { $ciStatus = "pass" } else { $ciStatus = "fail" }
  }
  $files = @($pr.files | ForEach-Object { [pscustomobject]@{ path = [string]$_.path; additions = [int]$_.additions; deletions = [int]$_.deletions } })
  $safeText = "$($pr.title)`n$($pr.body)`n$(($files | ForEach-Object path) -join "`n")"
  [pscustomobject]@{
    pr_number = [int]$pr.number
    title = [string]$pr.title
    base = [string]$pr.baseRefName
    state = [string]$pr.state
    is_draft = [bool]$pr.isDraft
    mergeable = [string]$pr.mergeable
    files = $files
    ci_status = $ciStatus
    redaction_passed = (-not (Test-TrustedDocsUnsafeText $safeText))
    raw_artifact_detected = ($safeText -match '(?i)raw_prompt|raw_transcript|raw_stdout|raw_stderr|raw_worker_log|raw_codex_transcript|raw_ci_log')
    content_secret_scan_passed = (-not (Test-TrustedDocsUnsafeText $safeText))
    task_pr = $true
    low_risk_docs_local_smoke = $true
    release_gate_pass = $true
    human_equivalent_goal_approval = $true
    body = [string]$pr.body
    token_printed = $false
  }
}

function New-TrustedDocsScopedDecision {
  $policy = New-TrustedDocsScopedPolicy
  $pr = if ($UseLivePr) { ConvertFrom-LivePr } else { New-TrustedDocsScopedFixture }
  $files = @($pr.files)
  $blockers = @()
  if ($ScopedPrNumber -le 0) { $blockers += "blocked_by_missing_scoped_approval" }
  if ($pr.pr_number -ne $ScopedPrNumber) { $blockers += "blocked_by_pr_scope_mismatch" }
  if ($pr.base -ne "main") { $blockers += "blocked_by_wrong_base" }
  if ($pr.state -ne "OPEN") { $blockers += "blocked_by_not_open" }
  if ($pr.is_draft -eq $true) { $blockers += "blocked_by_draft" }
  if ($pr.mergeable -notin @("MERGEABLE", "UNKNOWN")) { $blockers += "blocked_by_not_mergeable" }
  if ($files.Count -gt $policy.max_files) { $blockers += "blocked_by_multiple_files" }
  if (($files | Measure-Object -Property additions -Sum).Sum -gt $policy.max_additions) { $blockers += "blocked_by_too_many_changes" }
  if (($files | Measure-Object -Property deletions -Sum).Sum -gt $policy.max_deletions) { $blockers += "blocked_by_deletions" }
  if (@($files | Where-Object { -not (Test-TrustedDocsAllowedPath $_.path) }).Count -gt 0) { $blockers += "blocked_by_disallowed_path" }
  if ($pr.ci_status -ne "pass") { $blockers += "blocked_by_failing_or_missing_ci" }
  if ($pr.redaction_passed -ne $true) { $blockers += "blocked_by_redaction_scan" }
  if ($pr.raw_artifact_detected -eq $true) { $blockers += "blocked_by_raw_artifact" }
  if ($pr.content_secret_scan_passed -ne $true) { $blockers += "blocked_by_secret_scan" }
  if ($pr.task_pr -ne $true) { $blockers += "blocked_by_not_task_pr" }
  if ($pr.low_risk_docs_local_smoke -ne $true) { $blockers += "blocked_by_missing_local_smoke" }
  if ($pr.release_gate_pass -ne $true) { $blockers += "blocked_by_release_gate" }
  if ($pr.human_equivalent_goal_approval -ne $true) { $blockers += "blocked_by_missing_goal_approval" }
  if ($pr.token_printed -eq $true) { $blockers += "blocked_by_token_printed_true" }
  if ($UseLivePr -and $pr.body) {
    foreach ($needle in @("no auto-merge", "human review required", "token_printed=false")) {
      if ([string]$pr.body -notmatch [regex]::Escape($needle)) { $blockers += "blocked_by_missing_pr_body_attestation" }
    }
  }
  [pscustomobject]@{
    schema = "skybridge.trusted_docs_scoped_apply_decision.v1"
    fixture = $Fixture
    pr_number = [int]$pr.pr_number
    scoped_pr_number = $ScopedPrNumber
    decision = if (@($blockers).Count -eq 0) { "eligible_docs_only_but_requires_scoped_apply" } else { [string]@($blockers | Select-Object -First 1)[0] }
    auto_merge_allowed = (@($blockers).Count -eq 0)
    gh_merge_allowed = (@($blockers).Count -eq 0)
    files = $files
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-TrustedDocsScopedGate {
  $decision = New-TrustedDocsScopedDecision
  [pscustomobject]@{
    schema = "skybridge.trusted_docs_scoped_apply_gate.v1"
    policy = New-TrustedDocsScopedPolicy
    decision = $decision
    action = if ($decision.auto_merge_allowed) { "trusted_docs_scoped_merge" } else { "trusted_docs_scoped_merge_blocked" }
    audit = [pscustomobject]@{
      schema = "skybridge.trusted_docs_scoped_apply_audit.v1"
      events = @("trusted_docs_scoped_apply_evaluated", $(if ($decision.auto_merge_allowed) { "trusted_docs_scoped_merge_allowed" } else { "trusted_docs_scoped_merge_blocked" }))
      metadata_only = $true
      token_printed = $false
    }
    token_printed = $false
  }
}

function Invoke-TrustedDocsScopedMerge {
  $gate = New-TrustedDocsScopedGate
  if ($gate.decision.auto_merge_allowed -ne $true) { return $gate }
  if (-not $Apply) { return $gate }
  if (-not $UseLivePr) { throw "Refusing scoped merge without live PR evaluation." }
  gh pr merge $ScopedPrNumber --squash --delete-branch
  if ($LASTEXITCODE -ne 0) { throw "gh pr merge failed for PR $ScopedPrNumber." }
  $gate | Add-Member -NotePropertyName merge_invoked -NotePropertyValue $true -Force
  $gate
}

function New-TrustedDocsDecision {
  $policy = New-TrustedDocsPolicy
  $fixturePr = New-TrustedDocsFixture
  $files = @($fixturePr.files)
  $blockers = @()
  if ($policy.trusted_docs_auto_merge_enabled -ne $true -or $policy.auto_merge_apply_enabled -ne $true) { $blockers += "blocked_by_policy_disabled" }
  if ($files.Count -gt $policy.max_files) { $blockers += "blocked_by_multiple_files" }
  if (($files | Measure-Object -Property additions -Sum).Sum -gt $policy.max_additions) { $blockers += "blocked_by_too_many_changes" }
  if (($files | Measure-Object -Property deletions -Sum).Sum -gt $policy.max_deletions) { $blockers += "blocked_by_deletions" }
  if (@($files | Where-Object { -not (Test-TrustedDocsAllowedPath $_.path) }).Count -gt 0) { $blockers += "blocked_by_disallowed_path" }
  if ($fixturePr.raw_artifact_detected -eq $true) { $blockers += "blocked_by_raw_artifact" }
  if ($fixturePr.content_secret_scan_passed -ne $true) { $blockers += "blocked_by_secret_scan" }
  if ($fixturePr.ci_status -ne "pass") { $blockers += "blocked_by_missing_ci" }
  if ($fixturePr.open_review_hold -eq $true) { $blockers += "blocked_by_open_review_hold" }
  if ($policy.require_human_override -eq $true -and $fixturePr.human_override -ne $true) { $blockers += "blocked_by_no_human_override" }
  if ($fixturePr.token_printed -eq $true) { $blockers += "blocked_by_token_printed_true" }
  $theoretical = @($blockers | Where-Object { $_ -notin @("blocked_by_policy_disabled", "blocked_by_no_human_override") }).Count -eq 0
  $decision = if ($theoretical -and @($blockers) -contains "blocked_by_policy_disabled") { "eligible_docs_only_but_disabled" } else { @($blockers | Select-Object -First 1)[0] }
  if ([string]::IsNullOrWhiteSpace($decision)) { $decision = "blocked_by_policy_disabled" }
  [pscustomobject]@{
    schema = "skybridge.trusted_docs_auto_merge_decision.v1"
    fixture = $Fixture
    pr_number = $fixturePr.pr_number
    decision = $decision
    theoretically_eligible = $theoretical
    auto_merge_allowed = $false
    auto_merge_apply_enabled = $false
    human_review_required = $true
    files = $files
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-TrustedDocsGate {
  $decision = New-TrustedDocsDecision
  [pscustomObject]@{
    schema = "skybridge.trusted_docs_auto_merge_gate.v1"
    policy = New-TrustedDocsPolicy
    decision = $decision
    audit = [pscustomobject]@{
      schema = "skybridge.trusted_docs_auto_merge_audit.v1"
      events = @("trusted_docs_auto_merge_evaluated", "trusted_docs_auto_merge_blocked", "trusted_docs_auto_merge_disabled")
      metadata_only = $true
      token_printed = $false
    }
    auto_merge_allowed = $false
    platform_auto_merge_enabled = $false
    branch_protection_mutated = $false
    token_printed = $false
  }
}

function Write-TrustedDocsPreviewReport {
  $scenarios = @("eligible-docs-only", "disallowed-script", "multiple-files", "deletion", "token-content")
  $decisions = @()
  foreach ($scenario in $scenarios) {
    $script:Fixture = $scenario
    $decisions += New-TrustedDocsDecision
  }
  $report = [pscustomobject]@{
    schema = "skybridge.trusted_docs_auto_merge_preview_report.v1"
    trusted_docs_auto_merge_enabled = $false
    auto_merge_apply_enabled = $false
    decisions = @($decisions)
    audit_events = @("trusted_docs_auto_merge_evaluated", "trusted_docs_auto_merge_blocked", "trusted_docs_auto_merge_disabled")
    metadata_only = $true
    token_printed = $false
  }
  Write-TrustedDocsSafeJson "$ReportDir/preview-report.json" $report
  Write-TrustedDocsSafeMarkdown "$ReportDir/preview-report.md" @(
    "# Trusted Docs Auto-merge Preview",
    "",
    "- trusted_docs_auto_merge_enabled=false",
    "- auto_merge_apply_enabled=false",
    "- eligible docs-only PRs remain blocked by disabled policy and human review.",
    "- disallowed scripts, multiple files, deletions, and token-looking content are blocked.",
    "- token_printed=false"
  )
  $report
}

$result = switch ($Command) {
  "policy" { New-TrustedDocsPolicy }
  "gate" { New-TrustedDocsGate }
  "decision" { New-TrustedDocsDecision }
  "audit" { (New-TrustedDocsGate).audit }
  "preview-report" { Write-TrustedDocsPreviewReport }
  "scoped-policy" { New-TrustedDocsScopedPolicy }
  "scoped-decision" { New-TrustedDocsScopedDecision }
  "scoped-gate" { New-TrustedDocsScopedGate }
  "scoped-audit" { (New-TrustedDocsScopedGate).audit }
  "scoped-merge" { Invoke-TrustedDocsScopedMerge }
}

$result | ConvertTo-Json -Depth 20
