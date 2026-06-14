[CmdletBinding()]
param(
  [ValidateSet("launch-preview", "desktop-preview", "web-preview", "server-preview", "supervisor-preview", "resident-polling-preview", "safe-summary", "report")]
  [string]$Command = "launch-preview",
  [ValidateSet("dev-preview", "desktop-only", "web-control-plane-preview", "supervisor-heartbeat-preview", "resident-polling-preview", "full-local-preview")]
  [string]$Profile = "dev-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\launch-profiles"

function New-LaunchStep([string]$Id, [string]$PreviewCommand, [string]$Summary) {
  [pscustomobject]@{
    id = $Id
    preview_command = $PreviewCommand
    summary = $Summary
    applies_host_changes = $false
    starts_unbounded_worker = $false
    creates_workunit = $false
    creates_task = $false
    claims_task = $false
    token_printed = $false
  }
}

function New-LaunchPlan([string]$Kind) {
  $steps = switch ($Kind) {
    "desktop-preview" { @(New-LaunchStep "desktop-build-preview" "corepack pnpm -C apps/desktop build" "Build Desktop assets only; do not install or autostart.") }
    "web-preview" { @(New-LaunchStep "web-build-preview" "corepack pnpm --filter @skybridge-agent-hub/web build" "Build web console assets only.") }
    "server-preview" { @(New-LaunchStep "server-build-preview" "corepack pnpm --filter @skybridge-agent-hub/server build" "Build server package only; do not start production services.") }
    "supervisor-preview" { @(New-LaunchStep "supervisor-status-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-supervisor.ps1 -Command status" "Read local supervisor status only.") }
    "resident-polling-preview" { @(New-LaunchStep "resident-polling-status-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-resident-polling.ps1 -Command status" "Read resident polling preview state only.") }
    default {
      @(
        New-LaunchStep "desktop-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-launch.ps1 -Command desktop-preview" "Desktop preview."
        New-LaunchStep "web-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-launch.ps1 -Command web-preview" "Web preview."
        New-LaunchStep "server-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-launch.ps1 -Command server-preview" "Server preview."
      )
    }
  }
  [pscustomobject]@{
    schema = "skybridge.local_launch_preview.v1"
    command = $Kind
    profile = $Profile
    dry_run = $true
    preview_only = $true
    steps = $steps
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    trusted_docs_auto_merge_enabled = $false
    token_printed = $false
  }
}

function Write-LaunchReports($Report) {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $json = Join-Path $ReportDir "local-launch-preview-report.json"
  $md = Join-Path $ReportDir "local-launch-preview-report.md"
  $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $json -Encoding utf8
  @(
    "# Local Launch Preview Report",
    "",
    "- schema: skybridge.local_launch_report.v1",
    "- profile: $($Report.profile)",
    "- preview_only: true",
    "- dry_run: true",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath $md -Encoding utf8
}

$result = if ($Command -eq "safe-summary") {
  [pscustomobject]@{ ok = $true; profile = $Profile; preview_only = $true; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false }
} elseif ($Command -eq "report") {
  $report = [pscustomobject]@{
    schema = "skybridge.local_launch_report.v1"
    profile = $Profile
    dry_run = $true
    preview_only = $true
    plans = @("launch-preview", "desktop-preview", "web-preview", "server-preview", "supervisor-preview", "resident-polling-preview" | ForEach-Object { New-LaunchPlan $_ })
    token_printed = $false
  }
  Write-LaunchReports $report
  $report
} else {
  New-LaunchPlan $Command
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
