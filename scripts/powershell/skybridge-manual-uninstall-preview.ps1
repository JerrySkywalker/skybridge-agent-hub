[CmdletBinding()]
param(
  [ValidateSet("plan", "detect-preview", "remove-plan-preview", "cleanup-plan-preview", "safe-summary", "report")]
  [string]$Command = "plan",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\portable-package"

function New-Plan {
  [pscustomobject]@{
    schema = "skybridge.manual_uninstall_preview.v1"
    preview_only = $true
    detect_preview = "safe metadata only"
    remove_plan_preview = ".agent/tmp only; no deletion outside repository"
    cleanup_plan_preview = "preview only"
    registry_write = $false
    startup_write = $false
    scheduled_task_write = $false
    service_write = $false
    powercfg_write = $false
    uninstall_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $Plan = New-Plan
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $Plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "manual-uninstall-preview.json") -Encoding utf8
  @("# Manual Uninstall Preview", "", "- preview_only=true", "- uninstall_allowed=false", "- host_mutation_allowed=false", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "manual-uninstall-preview.md") -Encoding utf8
  $Plan
}

$Result = switch ($Command) {
  "plan" { New-Plan }
  "detect-preview" { New-Plan }
  "remove-plan-preview" { New-Plan }
  "cleanup-plan-preview" { New-Plan }
  "safe-summary" { [pscustomobject]@{ ok = $true; uninstall_allowed = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 20 } else { $Result | Format-List | Out-String }
