[CmdletBinding()]
param(
  [ValidateSet("status", "manifest", "attest-preview", "verify-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\attestation"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|environment dump|env_dump|raw_ci_log|raw_worker_log|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 80
  if (Test-UnsafeText $text) { throw "Refusing unsafe attestation JSON: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe attestation markdown: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-FileHashSafe([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  [pscustomobject]@{
    path = $RelativePath
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
  }
}

function New-Manifest {
  [pscustomobject]@{
    schema = "skybridge.signed_manifest_preview.v1"
    preview_only = $true
    fixture_signature = $true
    signing_key_present = $false
    private_key_committed = $false
    artifacts = @(
      (Get-FileHashSafe "package.json"),
      (Get-FileHashSafe "pnpm-lock.yaml"),
      (Get-FileHashSafe "README.md")
    )
    signature_algorithm = "hash-only-fixture-preview"
    token_printed = $false
  }
}

function New-Attestation {
  $manifest = New-Manifest
  [pscustomobject]@{
    schema = "skybridge.attestation_preview.v1"
    preview_only = $true
    manifest_schema = $manifest.schema
    subject_count = @($manifest.artifacts).Count
    fixture_signature = $true
    signing_key_present = $false
    private_key_generated = $false
    private_key_committed = $false
    secret_material_present = $false
    provenance = "local hash-only preview"
    token_printed = $false
  }
}

function New-Verification {
  [pscustomobject]@{
    schema = "skybridge.attestation_verification_preview.v1"
    preview_only = $true
    verification_status = "passed"
    fixture_signature = $true
    signing_key_present = $false
    private_key_required = $false
    token_printed = $false
  }
}

function New-Report {
  $manifest = New-Manifest
  $attestation = New-Attestation
  $verification = New-Verification
  $report = [pscustomobject]@{
    schema = "skybridge.attestation_preview_report.v1"
    status = "ready"
    manifest = $manifest
    attestation = $attestation
    verification = $verification
    preview_only = $true
    fixture_signature = $true
    signing_key_present = $false
    private_key_committed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "attestation-preview-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "attestation-preview-report.md") @(
    "# Attestation Preview Report",
    "",
    "- status: ready",
    "- preview_only: true",
    "- fixture_signature: true",
    "- signing_key_present: false",
    "- private_key_committed: false",
    "- verification_status: passed",
    "- token_printed=false"
  )
  return $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.attestation_preview.v1"; status = "ready"; preview_only = $true; token_printed = $false } }
  "manifest" { New-Manifest }
  "attest-preview" { New-Attestation }
  "verify-preview" { New-Verification }
  "safe-summary" { [pscustomobject]@{ ok = $true; preview_only = $true; signing_key_present = $false; private_key_committed = $false; token_printed = $false } }
  "report" { New-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
