[CmdletBinding()]
param(
  [ValidateSet("list", "run-fast", "run-release", "run-bootstrap-complete", "run-control-plane", "run-resident", "run-audit", "run-workunit-safe", "safe-summary", "report")]
  [string]$Command = "list",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = ".agent/tmp/smoke-matrix"

function Resolve-MatrixPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Test-MatrixUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|$tokenTrue"
}

function Write-MatrixSafeJson([string]$Path, $Value) {
  $full = Resolve-MatrixPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $jsonText = $Value | ConvertTo-Json -Depth 30
  if (Test-MatrixUnsafeText $jsonText) { throw "Refusing unsafe smoke matrix JSON: $Path" }
  Set-Content -LiteralPath $full -Value $jsonText -Encoding utf8
}

function Write-MatrixSafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-MatrixPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  if (Test-MatrixUnsafeText $text) { throw "Refusing unsafe smoke matrix markdown: $Path" }
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function Get-SmokeGroups {
  [ordered]@{
    "fast" = @("smoke-self-bootstrap-complete-status.ps1", "smoke-operator-cockpit-token-printed-false.ps1")
    "release" = @("smoke-self-bootstrap-release-report.ps1", "smoke-self-bootstrap-tag-preview.ps1")
    "bootstrap-complete" = @("smoke-self-bootstrap-complete-gate.ps1", "smoke-self-bootstrap-completed-run-registry.ps1", "smoke-self-bootstrap-no-workunit-c.ps1", "smoke-self-bootstrap-a-before-b-dependency.ps1", "smoke-bootstrap-complete-token-printed-false.ps1")
    "control-plane" = @("smoke-server-approved-workunit-token-printed-false.ps1")
    "resident" = @("smoke-resident-polling-token-printed-false.ps1")
    "pairing-approval" = @("smoke-server-approved-workunit-token-printed-false.ps1")
    "trusted-docs" = @("smoke-trusted-docs-scoped-apply-contract.ps1", "smoke-trusted-docs-scoped-merge-token-printed-false.ps1")
    "failure-budget" = @("smoke-failure-budget-token-printed-false.ps1")
    "evidence-retention" = @("smoke-evidence-retention-token-printed-false.ps1")
    "audit-redaction" = @("smoke-audit-token-printed-false.ps1")
    "workunit-safe" = @("smoke-server-approved-workunit-token-printed-false.ps1")
    "desktop" = @("smoke-desktop-operator-cockpit.ps1")
    "web" = @("smoke-web-operator-cockpit.ps1")
  }
}

function New-MatrixList {
  $groups = Get-SmokeGroups
  [pscustomobject]@{
    schema = "skybridge.smoke_matrix.v1"
    groups = @($groups.GetEnumerator() | ForEach-Object { [pscustomobject]@{ name = $_.Key; scripts = @($_.Value); count = @($_.Value).Count } })
    default_is_bounded = $true
    metadata_only = $true
    token_printed = $false
  }
}

function Invoke-SmokeGroup([string]$Name) {
  $groups = Get-SmokeGroups
  if (-not $groups.Contains($Name)) { throw "Unknown smoke group: $Name" }
  $results = @()
  foreach ($scriptName in @($groups[$Name])) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    $exists = Test-Path -LiteralPath $scriptPath
    $exitCode = 0
    if ($exists) {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath | Out-Null
      $exitCode = $LASTEXITCODE
    }
    $results += [pscustomobject]@{
      script = $scriptName
      exists = $exists
      passed = ($exists -and $exitCode -eq 0)
      exit_code = $exitCode
      metadata_only = $true
      token_printed = $false
    }
  }
  $passed = @($results | Where-Object { $_.passed -ne $true }).Count -eq 0
  [pscustomobject]@{
    schema = "skybridge.smoke_matrix_run.v1"
    group = $Name
    passed = $passed
    results = $results
    metadata_only = $true
    token_printed = $false
  }
}

function Write-MatrixReport($Value) {
  Write-MatrixSafeJson (Join-Path $ReportDir "smoke-matrix-report.json") $Value
  Write-MatrixSafeMarkdown (Join-Path $ReportDir "smoke-matrix-report.md") @(
    "# Smoke Matrix Report",
    "",
    "- schema: $($Value.schema)",
    "- command: $Command",
    "- bounded=true",
    "- metadata_only=true",
    "- token_printed=false"
  )
}

switch ($Command) {
  "list" { $result = New-MatrixList }
  "run-fast" { $result = Invoke-SmokeGroup "fast" }
  "run-release" { $result = Invoke-SmokeGroup "release" }
  "run-bootstrap-complete" { $result = Invoke-SmokeGroup "bootstrap-complete" }
  "run-control-plane" { $result = Invoke-SmokeGroup "control-plane" }
  "run-resident" { $result = Invoke-SmokeGroup "resident" }
  "run-audit" { $result = Invoke-SmokeGroup "audit-redaction" }
  "run-workunit-safe" { $result = Invoke-SmokeGroup "workunit-safe" }
  "safe-summary" { $result = New-MatrixList }
  "report" { $result = New-MatrixList }
}

Write-MatrixReport $result
if ($Json) {
  $result | ConvertTo-Json -Depth 30
} else {
  $result | Format-List | Out-String
}
