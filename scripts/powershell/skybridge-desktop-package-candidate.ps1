[CmdletBinding()]
param(
  [ValidateSet("status", "candidate-plan", "build-command-preview", "artifact-manifest-preview", "verify-metadata", "artifact-detect", "artifact-verify", "artifact-checksum-preview", "artifact-size-preview", "artifact-safe-summary", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\packaging-preview"

function New-ArtifactCandidate {
  [pscustomobject]@{
    schema = "skybridge.release_artifact_candidate.v1"
    artifact_id = "skybridge-desktop-local-preview"
    package_name = "SkyBridge Desktop"
    version = "0.1.0-productization-preview"
    target_os = "windows"
    target_arch = "x64"
    build_command_preview = "corepack pnpm -C apps/desktop build"
    expected_output_path_sanitized = "apps/desktop/dist"
    checksum_present = $false
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    token_printed = $false
  }
}

function New-ArtifactManifest {
  [pscustomobject]@{
    schema = "skybridge.release_artifact_manifest.v1"
    artifacts = @(New-ArtifactCandidate)
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    token_printed = $false
  }
}

function New-Verification {
  [pscustomobject]@{
    schema = "skybridge.artifact_verification_report.v1"
    ok = $true
    metadata_only = $true
    checksum_required_now = $false
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    writes_outside_repo = $false
    token_printed = $false
  }
}

function Get-RepoRelativePath([string]$Path) {
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
  if (-not $resolved) { return $null }
  $full = $resolved.Path
  if ($full.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ($full.Substring($RepoRoot.Length).TrimStart("\") -replace "\\", "/")
  }
  return "<outside-repo-redacted>"
}

function Get-DesktopArtifacts {
  $dist = Join-Path $RepoRoot "apps\desktop\dist"
  if (-not (Test-Path -LiteralPath $dist)) { return @() }
  @(Get-ChildItem -LiteralPath $dist -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 } | Select-Object -First 10)
}

function New-DesktopArtifactCandidate {
  $artifacts = Get-DesktopArtifacts
  if (@($artifacts).Count -eq 0) {
    return [pscustomobject]@{
      schema = "skybridge.desktop_artifact_candidate.v1"
      status = "artifact_absent"
      artifacts = @()
      upload_planned = $false
      install_planned = $false
      github_release_planned = $false
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.desktop_artifact_candidate.v1"
    status = "artifact_detected"
    artifacts = @($artifacts | ForEach-Object {
      [pscustomobject]@{
        path_sanitized = Get-RepoRelativePath $_.FullName
        size_bytes = $_.Length
        checksum_preview_present = $true
        token_printed = $false
      }
    })
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    token_printed = $false
  }
}

function New-ChecksumPreview {
  $artifacts = Get-DesktopArtifacts
  [pscustomobject]@{
    schema = "skybridge.desktop_artifact_checksum_preview.v1"
    checksum_algorithm = "SHA256"
    checksums = @($artifacts | Select-Object -First 5 | ForEach-Object {
      $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
      [pscustomobject]@{ path_sanitized = Get-RepoRelativePath $_.FullName; sha256 = $hash.Hash.ToLowerInvariant(); token_printed = $false }
    })
    upload_planned = $false
    install_planned = $false
    token_printed = $false
  }
}

function New-DesktopArtifactManifest {
  [pscustomobject]@{
    schema = "skybridge.desktop_artifact_manifest.v1"
    candidate = New-DesktopArtifactCandidate
    checksum_preview = New-ChecksumPreview
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    token_printed = $false
  }
}

function New-DesktopArtifactVerification {
  $candidate = New-DesktopArtifactCandidate
  [pscustomobject]@{
    schema = "skybridge.desktop_artifact_verification.v1"
    status = $candidate.status
    ok = $true
    artifact_absent_allowed = ($candidate.status -eq "artifact_absent")
    repo_local_only = $true
    upload_planned = $false
    install_planned = $false
    github_release_planned = $false
    signing_planned = $false
    moved_outside_repo = $false
    token_printed = $false
  }
}

function New-CandidatePlan {
  [pscustomobject]@{
    schema = "skybridge.desktop_package_candidate.v1"
    status = "candidate_metadata_ready"
    candidate = New-ArtifactCandidate
    manifest = New-ArtifactManifest
    verification = New-Verification
    token_printed = $false
  }
}

function Write-CandidateReports {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $plan = New-CandidatePlan
  $manifest = New-ArtifactManifest
  $desktopCandidate = New-DesktopArtifactCandidate
  $desktopVerification = New-DesktopArtifactVerification
  $desktopManifest = New-DesktopArtifactManifest
  $plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-package-candidate.json") -Encoding utf8
  $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "artifact-manifest-preview.json") -Encoding utf8
  $desktopCandidate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-artifact-candidate.json") -Encoding utf8
  $desktopVerification | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-artifact-verification.json") -Encoding utf8
  @(
    "# Desktop Artifact Manifest",
    "",
    "- schema: skybridge.desktop_artifact_manifest.v1",
    "- status: $($desktopCandidate.status)",
    "- repo_local_only=true",
    "- upload_planned=false",
    "- install_planned=false",
    "- github_release_planned=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-artifact-manifest.md") -Encoding utf8
  @(
    "# Desktop Package Candidate",
    "",
    "- schema: skybridge.desktop_package_candidate.v1",
    "- status: candidate_metadata_ready",
    "- upload_planned=false",
    "- install_planned=false",
    "- github_release_planned=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-package-candidate.md") -Encoding utf8
  $plan
}

$result = switch ($Command) {
  "status" { New-CandidatePlan }
  "candidate-plan" { New-CandidatePlan }
  "build-command-preview" { (New-ArtifactCandidate) }
  "artifact-manifest-preview" { New-ArtifactManifest }
  "verify-metadata" { New-Verification }
  "artifact-detect" { New-DesktopArtifactCandidate }
  "artifact-verify" { New-DesktopArtifactVerification }
  "artifact-checksum-preview" { New-ChecksumPreview }
  "artifact-size-preview" { [pscustomobject]@{ schema = "skybridge.desktop_artifact_size_preview.v1"; artifacts = @((New-DesktopArtifactCandidate).artifacts); token_printed = $false } }
  "artifact-safe-summary" { [pscustomobject]@{ ok = $true; upload_planned = $false; install_planned = $false; github_release_planned = $false; signing_planned = $false; moved_outside_repo = $false; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; upload_planned = $false; install_planned = $false; github_release_planned = $false; token_printed = $false } }
  "report" { Write-CandidateReports }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
