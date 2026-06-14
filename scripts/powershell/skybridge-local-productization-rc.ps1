[CmdletBinding()]
param(
  [ValidateSet("status", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\product-readiness"

function Get-Commit {
  (& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim()
}

function New-RcReport {
  [pscustomobject]@{
    schema = "skybridge.local_productization_rc_report.v1"
    rc_version = "v1.1.0-local-productization-rc"
    commit = Get-Commit
    runtime_candidate_status = "bounded_non_worker_candidate"
    config_wizard_status = "preview_with_validation_and_redaction"
    packaging_candidate_status = "repo_local_artifact_candidate_or_absent"
    diagnostics_status = "safe_metadata_only"
    backup_restore_preview_status = "safe_metadata_only"
    disabled_capabilities = @("codex_worker_execution", "workunit_apply", "task_claim", "queue_apply", "remote_execution", "arbitrary_command_dispatch", "global_trusted_docs_auto_merge")
    known_limitations = @("no installer", "no service install", "no remote update", "no artifact upload")
    next_recommended_goals = @("installer signing plan", "authenticated local pairing", "operator-controlled service install preview")
    token_printed = $false
  }
}

function Write-RcReport {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report = New-RcReport
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "local-productization-rc-report.json") -Encoding utf8
  @(
    "# Local Productization RC Report",
    "",
    "- schema: skybridge.local_productization_rc_report.v1",
    "- rc_version: $($report.rc_version)",
    "- commit: $($report.commit)",
    "- runtime_candidate_status: $($report.runtime_candidate_status)",
    "- config_wizard_status: $($report.config_wizard_status)",
    "- packaging_candidate_status: $($report.packaging_candidate_status)",
    "- diagnostics_status: safe_metadata_only",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "local-productization-rc-report.md") -Encoding utf8
  $report
}

$result = switch ($Command) {
  "status" { New-RcReport }
  "report" { Write-RcReport }
  "safe-summary" { [pscustomobject]@{ ok = $true; rc_version = "v1.1.0-local-productization-rc"; token_printed = $false } }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
