[CmdletBinding()]
param(
  [ValidateSet("backup-plan-preview", "restore-plan-preview", "export-safe-metadata-preview", "verify-backup-policy", "safe-summary", "report")]
  [string]$Command = "backup-plan-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\upgrade-preview"

function New-BackupPolicy {
  [pscustomobject]@{
    schema = "skybridge.backup_restore_preview.v1"
    include = @("safe .agent/tmp metadata reports", "release reports", "diagnostics reports", "product readiness reports", "evidence indexes", "audit summaries")
    exclude = @("raw logs", "raw prompts", "raw transcripts", "raw stdout/stderr", "raw worker logs", "raw CI logs", "env dumps", "secrets", "tokens", "Authorization headers", "cookies", "private keys", "raw pairing codes", "node_modules", "target", "build artifacts")
    raw_artifacts_included = $false
    env_dumps_included = $false
    secrets_included = $false
    tokens_included = $false
    writes_external_locations = $false
    token_printed = $false
  }
}

function New-RestorePlan {
  [pscustomobject]@{
    schema = "skybridge.restore_plan_preview.v1"
    preview_only = $true
    restore_safe_metadata_only = $true
    restore_secrets = $false
    overwrite_runtime_logs = $false
    token_printed = $false
  }
}

function Write-BackupReport {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report = [pscustomobject]@{
    schema = "skybridge.backup_restore_report.v1"
    backup_policy = New-BackupPolicy
    restore_plan = New-RestorePlan
    token_printed = $false
  }
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "backup-restore-preview.json") -Encoding utf8
  @(
    "# Backup Restore Preview",
    "",
    "- schema: skybridge.backup_restore_report.v1",
    "- raw_artifacts_included=false",
    "- env_dumps_included=false",
    "- secrets_included=false",
    "- tokens_included=false",
    "- writes_external_locations=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "backup-restore-preview.md") -Encoding utf8
  $report
}

$result = switch ($Command) {
  "backup-plan-preview" { New-BackupPolicy }
  "restore-plan-preview" { New-RestorePlan }
  "export-safe-metadata-preview" { New-BackupPolicy }
  "verify-backup-policy" { [pscustomobject]@{ ok = $true; policy = New-BackupPolicy; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; raw_artifacts_included = $false; env_dumps_included = $false; secrets_included = $false; token_printed = $false } }
  "report" { Write-BackupReport }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
