[CmdletBinding()]
param(
  [ValidateSet("desktop-build-preview", "artifact-plan", "package-metadata-preview", "release-artifact-preview", "safe-summary", "report")]
  [string]$Command = "desktop-build-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\packaging-preview"

function New-PackagingPreview([string]$Kind) {
  [pscustomobject]@{
    schema = "skybridge.desktop_packaging_preview.v1"
    command = $Kind
    desktop_build_preview = "corepack pnpm -C apps/desktop build"
    artifact_plan = @("apps/desktop/dist", "apps/desktop/src-tauri/target metadata only")
    package_metadata = @{ product = "SkyBridge Agent Hub"; package_scope = "@skybridge-agent-hub/*"; channel = "local-preview" }
    uploads_artifacts = $false
    creates_github_release = $false
    installs_package = $false
    mutates_system_settings = $false
    metadata_only = $true
    token_printed = $false
  }
}

function Write-PackagingReport {
  $report = New-PackagingPreview "report"
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-packaging-preview.json") -Encoding utf8
  @(
    "# Desktop Packaging Preview",
    "",
    "- schema: skybridge.desktop_packaging_preview.v1",
    "- metadata_only=true",
    "- uploads_artifacts=false",
    "- creates_github_release=false",
    "- installs_package=false",
    "- mutates_system_settings=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-packaging-preview.md") -Encoding utf8
  $report
}

$result = if ($Command -eq "report") { Write-PackagingReport } else { New-PackagingPreview $Command }
if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
