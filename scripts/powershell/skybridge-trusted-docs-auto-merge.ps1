[CmdletBinding()]
param(
  [ValidateSet("policy", "gate", "decision", "audit", "preview-report")]
  [string]$Command = "policy",
  [ValidateSet("eligible-docs-only", "disallowed-script", "multiple-files", "deletion", "token-content", "missing-ci", "open-review-hold", "no-human-override")]
  [string]$Fixture = "eligible-docs-only",
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

function Test-TrustedDocsAllowedPath([string]$Path) {
  $p = $Path.Replace("\", "/")
  return ($p -eq "README.md" -or $p -like "docs/*")
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
}

$result | ConvertTo-Json -Depth 20
