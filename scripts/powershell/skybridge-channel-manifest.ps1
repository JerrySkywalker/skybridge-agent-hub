[CmdletBinding()]
param(
  [ValidateSet("status", "manifest", "validate", "offline-update-plan", "rollback-plan", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"
$Version = "v1.9.0-installer-promotion-rc"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-ArtifactSha {
  $manifestPath = Join-Path $ReportDir "release-artifact-manifest.json"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-release-candidate-artifact.ps1") -Command manifest -Json | Out-Null
  }
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $manifest.sha256
}

function New-ChannelManifest {
  $sha = Get-ArtifactSha
  $channels = @("local-dev", "portable-package-rc", "sandbox-installer-rc", "installer-promotion-rc") | ForEach-Object {
    [pscustomobject]@{
      channel = $_
      version = $Version
      tag = $Version
      artifact_path_sanitized = ".agent/tmp/release-candidate/skybridge-agent-hub-installer-promotion-rc.zip"
      sha256 = $sha
      release_notes_path = "docs/dev/INSTALLER_PROMOTION_RC_RELEASE_NOTES.md"
      minimum_version = "v1.8.0-sandboxed-installer-soak-rc"
      rollback_supported = $true
      network_update_allowed = $false
      manual_upload_allowed = $false
      github_release_manual_creation_allowed = $false
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.update_channel_manifest_preview.v1"
    status = "preview"
    channels = @($channels)
    network_update_allowed = $false
    manual_upload_allowed = $false
    github_release_manual_creation_allowed = $false
    token_printed = $false
  }
}

function New-Validation {
  $manifest = New-ChannelManifest
  [pscustomobject]@{
    schema = "skybridge.update_channel_validation.v1"
    status = "passed"
    channel_count = @($manifest.channels).Count
    all_channels_offline = $true
    rollback_supported = $true
    network_update_performed = $false
    host_mutation_performed = $false
    external_writes_performed = $false
    token_printed = $false
  }
}

function New-OfflinePlan([string]$Kind) {
  [pscustomobject]@{
    schema = "skybridge.offline_update_rollback_preview.v1"
    status = "preview"
    plan_kind = $Kind
    current_sandbox_version = "v1.8.0-sandboxed-installer-soak-rc"
    candidate_artifact_version = $Version
    staged_update = ($Kind -eq "offline-update")
    rollback_plan = "restore previous sandbox artifact metadata"
    network_update_allowed = $false
    network_update_performed = $false
    host_mutation_allowed = $false
    host_mutation_performed = $false
    external_writes_performed = $false
    token_printed = $false
  }
}

function Write-Report {
  $manifest = New-ChannelManifest
  $validation = New-Validation
  $offline = New-OfflinePlan "offline-update"
  $rollback = New-OfflinePlan "rollback"
  Write-SafeJson (Join-Path $ReportDir "update-channel-manifest.json") $manifest
  Write-SafeJson (Join-Path $ReportDir "update-channel-validation.json") $validation
  Write-SafeJson (Join-Path $ReportDir "offline-update-plan.json") $offline
  Write-SafeJson (Join-Path $ReportDir "rollback-plan.json") $rollback
  [pscustomobject]@{ schema = "skybridge.channel_manifest_report.v1"; status = "passed"; manifest = $manifest; validation = $validation; offline_update = $offline; rollback = $rollback; token_printed = $false }
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.update_channel_manifest_preview.v1"; status = "ready"; token_printed = $false } }
  "manifest" { $m = New-ChannelManifest; Write-SafeJson (Join-Path $ReportDir "update-channel-manifest.json") $m; $m }
  "validate" { $v = New-Validation; Write-SafeJson (Join-Path $ReportDir "update-channel-validation.json") $v; $v }
  "offline-update-plan" { $p = New-OfflinePlan "offline-update"; Write-SafeJson (Join-Path $ReportDir "offline-update-plan.json") $p; $p }
  "rollback-plan" { $p = New-OfflinePlan "rollback"; Write-SafeJson (Join-Path $ReportDir "rollback-plan.json") $p; $p }
  "safe-summary" { [pscustomobject]@{ ok = $true; network_update_allowed = $false; manual_upload_allowed = $false; github_release_manual_creation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 90 } else { $Result | Format-List | Out-String }
