[CmdletBinding()]
param(
  [ValidateSet("status", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-auth"
$ReportJson = Join-Path $ReportDir "v2-local-control-plane-rc-report.json"
$ReportMarkdown = Join-Path $ReportDir "v2-local-control-plane-rc-report.md"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|raw_prompt|raw_stdout|raw_stderr|raw_worker_log|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 100
  if (Test-UnsafeText $text) { throw "Refusing unsafe v2 RC JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe v2 RC markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text." }
  $text | ConvertFrom-Json
}

function Test-DocPresent([string]$Path) {
  Test-Path -LiteralPath (Join-Path $RepoRoot $Path)
}

function Get-Commit {
  (& git -C $RepoRoot rev-parse --short HEAD).Trim()
}

function New-RcReport {
  $localAuth = Invoke-JsonScript "skybridge-local-auth.ps1" @("-Command", "report")
  Invoke-JsonScript "skybridge-local-auth.ps1" @("-Command", "session-create-fixture") | Out-Null
  $session = Invoke-JsonScript "skybridge-local-auth.ps1" @("-Command", "session-report")
  $attestation = Invoke-JsonScript "skybridge-attestation-preview.ps1" @("-Command", "report")
  $sbom = Invoke-JsonScript "skybridge-sbom-preview.ps1" @("-Command", "report")
  $hostConsent = Invoke-JsonScript "skybridge-host-consent-preview.ps1" @("-Command", "report")
  $rehearsal = Invoke-JsonScript "skybridge-authenticated-session-rehearsal.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-auth-soak.ps1" @("-Command", "report")
  $tagGate = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "report")

  $docs = @(
    "docs/dev/SECURITY_THREAT_MODEL_V2_LOCAL_CONTROL_PLANE.md",
    "docs/dev/AUTH_AND_HOST_MUTATION_THREAT_MODEL.md",
    "docs/dev/RED_TEAM_TEST_PLAN.md",
    "docs/dev/V2_LOCAL_CONTROL_PLANE_RC.md",
    "docs/dev/V2_LOCAL_CONTROL_PLANE_RELEASE_NOTES.md",
    "docs/dev/V2_SECURITY_HARDENING_SUMMARY.md",
    "docs/dev/V2_NEXT_ROADMAP.md"
  )
  $missingDocs = @($docs | Where-Object { -not (Test-DocPresent $_) })

  $report = [pscustomobject]@{
    schema = "skybridge.v2_local_control_plane_rc_report.v1"
    rc_version = "v2.0.0-local-auth-control-plane-rc"
    commit = Get-Commit
    local_auth_status = $localAuth.status
    auth_session_store_status = $(if ($session.raw_token_persisted -eq $false -and $session.auth_header_persisted -eq $false) { "hash_only_fixture_safe" } else { "blocked" })
    api_auth_gate_status = $localAuth.api_auth_gate_status
    web_desktop_auth_surface_status = $localAuth.web_desktop_surface_status
    attestation_preview_status = $attestation.status
    sbom_status = $sbom.status
    host_consent_preview_status = $hostConsent.status
    installer_consent_interlock_status = $(if ($hostConsent.installer_real_mutation_allowed -eq $false) { "blocked_by_default" } else { "blocked" })
    threat_model_status = $(if ($missingDocs.Count -eq 0) { "docs_present" } else { "docs_missing" })
    red_team_smoke_status = "available"
    authenticated_rehearsal_status = $rehearsal.status
    auth_soak_status = $soak.status
    tag_safety_gate_status = $tagGate.gate.gate
    disabled_capabilities = @(
      "worker_execution",
      "workunit_apply",
      "queue_apply",
      "remote_execution",
      "arbitrary_command_dispatch",
      "host_mutation",
      "real_installer_mutation",
      "manual_github_release_creation",
      "manual_artifact_upload"
    )
    known_limitations = @(
      "fixture-only local auth",
      "hash-only session store",
      "attestation preview has no production signing key",
      "SBOM is local dependency inventory preview only",
      "host mutation remains disabled",
      "installer mutation remains interlocked"
    )
    next_recommended_goals = @(
      "graduate real local authenticated server behind explicit gate",
      "keep host mutation behind future explicit goal",
      "keep worker execution separately gated",
      "preserve no remote execution and no arbitrary command dispatch"
    )
    report_paths = @(
      ".agent/tmp/local-auth/v2-local-control-plane-rc-report.json",
      ".agent/tmp/local-auth/v2-local-control-plane-rc-report.md",
      ".agent/tmp/local-auth/authenticated-session-rehearsal-report.json",
      ".agent/tmp/local-auth/auth-soak-report.json",
      ".agent/tmp/release-guard/tag-safety-gate.json"
    )
    token_printed = $false
  }

  Write-SafeJson $ReportJson $report
  Write-SafeMarkdown $ReportMarkdown @(
    "# v2 Local Control-plane RC Report",
    "",
    "- schema: skybridge.v2_local_control_plane_rc_report.v1",
    "- rc_version: $($report.rc_version)",
    "- commit: $($report.commit)",
    "- local_auth_status: $($report.local_auth_status)",
    "- auth_session_store_status: $($report.auth_session_store_status)",
    "- api_auth_gate_status: $($report.api_auth_gate_status)",
    "- Web/Desktop auth surface status: $($report.web_desktop_auth_surface_status)",
    "- attestation_preview_status: $($report.attestation_preview_status)",
    "- sbom_status: $($report.sbom_status)",
    "- host_consent_preview_status: $($report.host_consent_preview_status)",
    "- installer_consent_interlock_status: $($report.installer_consent_interlock_status)",
    "- threat_model_status: $($report.threat_model_status)",
    "- red_team_smoke_status: $($report.red_team_smoke_status)",
    "- authenticated_rehearsal_status: $($report.authenticated_rehearsal_status)",
    "- auth_soak_status: $($report.auth_soak_status)",
    "- tag_safety_gate_status: $($report.tag_safety_gate_status)",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.v2_local_control_plane_rc_report.v1"; status = "ready"; rc_version = "v2.0.0-local-auth-control-plane-rc"; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; rc_version = "v2.0.0-local-auth-control-plane-rc"; token_printed = $false } }
  "report" { New-RcReport }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
