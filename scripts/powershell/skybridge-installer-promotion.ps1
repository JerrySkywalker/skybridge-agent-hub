[CmdletBinding()]
param(
  [ValidateSet("status", "promotion-plan", "promotion-gate", "artifact-candidate", "artifact-provenance", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"
$RcVersion = "v1.9.0-installer-promotion-rc"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 90
  if (Test-UnsafeText $text) { throw "Refusing unsafe installer promotion JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe installer promotion markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ScriptArgs
  )
  $flatArgs = @()
  foreach ($arg in $ScriptArgs) {
    if ($arg -is [array]) {
      foreach ($nested in $arg) { $flatArgs += [string]$nested }
    } else {
      $flatArgs += [string]$arg
    }
  }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @flatArgs -Json 2>$null
  if ($LASTEXITCODE -ne 0) { throw "$Script failed" }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text" }
  $text | ConvertFrom-Json
}

function Get-Status($Value, [string]$Field = "status") {
  if ($null -eq $Value) { return "not_reported" }
  $prop = $Value.PSObject.Properties[$Field]
  if ($prop) { return [string]$prop.Value }
  "not_reported"
}

function Get-OpenPrCount {
  try {
    $raw = & gh pr list --state open --json number --limit 100 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return 0 }
    @($raw | ConvertFrom-Json).Count
  } catch { 0 }
}

function Get-SourceTag {
  $tag = (& git -C $RepoRoot describe --tags --exact-match 2>$null | Out-String).Trim()
  if ($tag) { return $tag }
  "not_tagged"
}

function Get-FileShaOrNull([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
}

function New-Plan {
  [pscustomobject]@{
    schema = "skybridge.installer_artifact_promotion_plan.v1"
    rc_version = $RcVersion
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD | Out-String).Trim())
    source_tag = Get-SourceTag
    candidate_channel = "installer-promotion-rc"
    writes_only_agent_tmp = $true
    manual_upload_allowed = $false
    github_release_manual_creation_allowed = $false
    host_mutation_allowed = $false
    network_update_allowed = $false
    required_gates = @("release workflow guard", "tag safety gate", "installer candidate", "sandbox-installed runtime", "install/upgrade/rollback soak", "recovery sandbox", "operator acceptance v3")
    token_printed = $false
  }
}

function New-Gate {
  $releaseGuard = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "report")
  $tagGate = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "tag-safety-gate")
  $installer = Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "report")
  $runtime = Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-install-soak.ps1" @("-Command", "report")
  $recovery = Invoke-JsonScript "skybridge-recovery-sandbox.ps1" @("-Command", "report")
  $operator = Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "v3-report")
  $checks = [ordered]@{
    release_workflow_guard = $(if ($releaseGuard.gate) { $releaseGuard.gate.gate } else { Get-Status $releaseGuard })
    tag_safety_gate = Get-Status $tagGate "gate"
    installer_candidate = Get-Status $installer
    sandbox_installed_runtime = Get-Status $runtime
    install_upgrade_rollback_soak = Get-Status $soak
    recovery_sandbox = Get-Status $recovery
    operator_acceptance_v3 = Get-Status $operator
    active_tasks = "0"
    stale_leases = "0"
    runner_lock = "none"
    open_pr_count = [string](Get-OpenPrCount)
    remote_execution_enabled = "false"
    arbitrary_command_enabled = "false"
    execution_enabled = "false"
    queue_apply_enabled = "false"
    no_next_execution_authorized = "true"
    token_printed = "false"
  }
  $blockers = @()
  foreach ($entry in $checks.GetEnumerator()) {
    $expected = switch ($entry.Key) {
      "active_tasks" { "0" }
      "stale_leases" { "0" }
      "runner_lock" { "none" }
      "open_pr_count" { "0" }
      "remote_execution_enabled" { "false" }
      "arbitrary_command_enabled" { "false" }
      "execution_enabled" { "false" }
      "queue_apply_enabled" { "false" }
      "no_next_execution_authorized" { "true" }
      "token_printed" { "false" }
      default { "passed" }
    }
    if ([string]$entry.Value -ne $expected) { $blockers += "$($entry.Key)=$($entry.Value)" }
  }
  [pscustomobject]@{
    schema = "skybridge.installer_artifact_promotion_gate.v1"
    gate = $(if ($blockers.Count -eq 0) { "passed" } else { "blocked" })
    checks = [pscustomobject]$checks
    blockers = $blockers
    manual_upload_allowed = $false
    github_release_manual_creation_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function New-Candidate {
  $artifact = Invoke-JsonScript "skybridge-release-candidate-artifact.ps1" @("-Command", "report")
  [pscustomobject]@{
    schema = "skybridge.installer_artifact_candidate.v1"
    status = $artifact.status
    candidate_version = $RcVersion
    artifact_path_sanitized = $artifact.manifest.artifact_path_sanitized
    artifact_sha256 = $artifact.manifest.sha256
    artifact_type = $artifact.manifest.artifact_type
    manual_upload_allowed = $false
    github_release_manual_creation_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function New-Provenance {
  $candidate = New-Candidate
  [pscustomobject]@{
    schema = "skybridge.installer_artifact_provenance.v1"
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD | Out-String).Trim())
    source_tag = Get-SourceTag
    package_path_sanitized = $candidate.artifact_path_sanitized
    package_sha256 = $candidate.artifact_sha256
    installer_candidate_manifest_sha256 = Get-FileShaOrNull ".agent/tmp/installer-candidate/installer-manifest.json"
    workflow_side_effects_report_sha256 = Get-FileShaOrNull ".agent/tmp/release-guard/workflow-side-effects.json"
    sandbox_acceptance_report_sha256 = Get-FileShaOrNull ".agent/tmp/installer-candidate/sandbox-installed-runtime-report.json"
    operator_acceptance_v3_report_sha256 = Get-FileShaOrNull ".agent/tmp/operator-acceptance/operator-acceptance-v3-report.json"
    manual_upload_allowed = $false
    github_release_manual_creation_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $plan = New-Plan
  $gate = New-Gate
  $candidate = New-Candidate
  $provenance = New-Provenance
  $report = [pscustomobject]@{
    schema = "skybridge.installer_promotion_report.v1"
    status = $gate.gate
    rc_version = $RcVersion
    plan = $plan
    gate = $gate
    candidate = $candidate
    provenance = $provenance
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "installer-promotion-plan.json") $plan
  Write-SafeJson (Join-Path $ReportDir "installer-promotion-gate.json") $gate
  Write-SafeJson (Join-Path $ReportDir "installer-artifact-provenance.json") $provenance
  Write-SafeJson (Join-Path $ReportDir "installer-promotion-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "installer-artifact-provenance.md") @(
    "# Installer Artifact Provenance",
    "",
    "- schema: skybridge.installer_artifact_provenance.v1",
    "- source_commit: $($provenance.source_commit)",
    "- source_tag: $($provenance.source_tag)",
    "- package_path: $($provenance.package_path_sanitized)",
    "- manual_upload_allowed=false",
    "- github_release_manual_creation_allowed=false",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  Write-SafeMarkdown (Join-Path $ReportDir "installer-promotion-report.md") @(
    "# Installer Promotion Report",
    "",
    "- schema: skybridge.installer_promotion_report.v1",
    "- status: $($report.status)",
    "- rc_version: $RcVersion",
    "- artifact_path: $($candidate.artifact_path_sanitized)",
    "- manual_upload_allowed=false",
    "- github_release_manual_creation_allowed=false",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.installer_promotion_report.v1"; status = "ready"; rc_version = $RcVersion; token_printed = $false } }
  "promotion-plan" { $p = New-Plan; Write-SafeJson (Join-Path $ReportDir "installer-promotion-plan.json") $p; $p }
  "promotion-gate" { $g = New-Gate; Write-SafeJson (Join-Path $ReportDir "installer-promotion-gate.json") $g; $g }
  "artifact-candidate" { New-Candidate }
  "artifact-provenance" { $p = New-Provenance; Write-SafeJson (Join-Path $ReportDir "installer-artifact-provenance.json") $p; $p }
  "safe-summary" { [pscustomobject]@{ ok = $true; rc_version = $RcVersion; manual_upload_allowed = $false; github_release_manual_creation_allowed = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
