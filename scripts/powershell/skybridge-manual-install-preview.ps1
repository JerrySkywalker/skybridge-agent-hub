[CmdletBinding()]
param(
  [ValidateSet("plan", "verify-package", "copy-plan-preview", "shortcut-plan-preview", "start-menu-plan-preview", "path-plan-preview", "safe-summary", "report")]
  [string]$Command = "plan",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\portable-package"

function New-Plan {
  [pscustomobject]@{
    schema = "skybridge.manual_install_preview.v1"
    preview_only = $true
    package_root_sanitized = ".agent/tmp/portable-package"
    copy_plan_preview = ".agent/tmp only; no install copy outside repository"
    shortcut_plan_preview = "preview only; no shortcut creation"
    start_menu_plan_preview = "preview only; no Start Menu write"
    path_plan_preview = "preview only; no PATH mutation"
    registry_write = $false
    startup_write = $false
    scheduled_task_write = $false
    service_write = $false
    powercfg_write = $false
    network_used = $false
    install_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $Plan = New-Plan
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $Plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "manual-install-preview.json") -Encoding utf8
  @("# Manual Install Preview", "", "- preview_only=true", "- install_allowed=false", "- host_mutation_allowed=false", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "manual-install-preview.md") -Encoding utf8
  $Plan
}

$Result = switch ($Command) {
  "plan" { New-Plan }
  "verify-package" { & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-portable-package.ps1") -Command verify -Json | ConvertFrom-Json }
  "copy-plan-preview" { New-Plan }
  "shortcut-plan-preview" { New-Plan }
  "start-menu-plan-preview" { New-Plan }
  "path-plan-preview" { New-Plan }
  "safe-summary" { [pscustomobject]@{ ok = $true; install_allowed = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 20 } else { $Result | Format-List | Out-String }
