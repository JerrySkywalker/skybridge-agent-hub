[CmdletBinding()]
param(
  [ValidateSet("channel-status", "manifest-preview", "update-check-preview", "upgrade-plan-preview", "rollback-plan-preview", "safe-summary", "report")]
  [string]$Command = "channel-status",
  [ValidateSet("local-dev", "bootstrap-complete", "productization-preview")]
  [string]$Channel = "productization-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\upgrade-preview"

function New-Channel {
  [pscustomobject]@{
    schema = "skybridge.release_channel.v1"
    channel = $Channel
    network_update = $false
    github_release_creation = $false
    binary_install = $false
    self_modification = $false
    service_registry_startup_mutation = $false
    token_printed = $false
  }
}

function New-UpdateManifest {
  [pscustomobject]@{
    schema = "skybridge.update_manifest_preview.v1"
    channel = New-Channel
    available_version = "local-preview"
    update_check_preview_only = $true
    network_request_planned = $false
    install_planned = $false
    token_printed = $false
  }
}

function New-UpgradePlan {
  [pscustomobject]@{
    schema = "skybridge.upgrade_plan_preview.v1"
    steps = @("git pull --ff-only after clean tree", "corepack pnpm install", "corepack pnpm check", "regenerate safe reports")
    network_update = $false
    binary_install = $false
    service_mutation = $false
    token_printed = $false
  }
}

function New-RollbackPlan {
  [pscustomobject]@{
    schema = "skybridge.rollback_plan_preview.v1"
    steps = @("return to previous git commit", "rerun safe diagnostics", "do not restore secrets from product reports")
    destructive_cleanup = $false
    token_printed = $false
  }
}

function Write-UpdateReport {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report = [pscustomobject]@{
    schema = "skybridge.update_preview_report.v1"
    channel = New-Channel
    manifest = New-UpdateManifest
    upgrade_plan = New-UpgradePlan
    rollback_plan = New-RollbackPlan
    token_printed = $false
  }
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "update-preview-report.json") -Encoding utf8
  @(
    "# Update Preview Report",
    "",
    "- schema: skybridge.update_preview_report.v1",
    "- channel: $Channel",
    "- network_update=false",
    "- binary_install=false",
    "- github_release_creation=false",
    "- service_registry_startup_mutation=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "update-preview-report.md") -Encoding utf8
  $report
}

$result = switch ($Command) {
  "channel-status" { New-Channel }
  "manifest-preview" { New-UpdateManifest }
  "update-check-preview" { New-UpdateManifest }
  "upgrade-plan-preview" { New-UpgradePlan }
  "rollback-plan-preview" { New-RollbackPlan }
  "safe-summary" { [pscustomobject]@{ ok = $true; network_update = $false; binary_install = $false; github_release_creation = $false; token_printed = $false } }
  "report" { Write-UpdateReport }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
