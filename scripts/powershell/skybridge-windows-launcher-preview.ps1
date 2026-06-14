[CmdletBinding()]
param(
  [ValidateSet("launcher-preview", "shortcut-preview", "startup-entry-preview", "scheduled-task-preview", "service-preview", "uninstall-preview", "safe-summary", "report")]
  [string]$Command = "launcher-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\windows-launcher-preview"

function New-WindowsPreview([string]$Kind) {
  [pscustomobject]@{
    schema = "skybridge.windows_launcher_preview.v1"
    command = $Kind
    dry_run = $true
    preview_only = $true
    planned_metadata = @(
      "Create a local launcher script inside the repository.",
      "Create optional shortcut metadata for operator review.",
      "Keep startup, scheduled task and service actions unapplied."
    )
    registry_mutation = $false
    startup_folder_write = $false
    scheduled_task_creation = $false
    service_creation = $false
    powercfg_mutation = $false
    sleep_or_standby_mutation = $false
    applies_host_changes = $false
    token_printed = $false
  }
}

function Write-WindowsPreviewReport {
  $report = New-WindowsPreview "report"
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "windows-launcher-preview.json") -Encoding utf8
  @(
    "# Windows Launcher Preview",
    "",
    "- schema: skybridge.windows_launcher_preview.v1",
    "- dry_run=true",
    "- registry_mutation=false",
    "- startup_folder_write=false",
    "- scheduled_task_creation=false",
    "- service_creation=false",
    "- powercfg_mutation=false",
    "- sleep_or_standby_mutation=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "windows-launcher-preview.md") -Encoding utf8
  $report
}

$result = if ($Command -eq "report") { Write-WindowsPreviewReport } else { New-WindowsPreview $Command }
if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
