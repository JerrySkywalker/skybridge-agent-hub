[CmdletBinding()]
param(
  [ValidateSet("status", "candidate-plan", "build-command-preview", "artifact-manifest-preview", "verify-metadata", "safe-summary", "report")]
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
  $plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "desktop-package-candidate.json") -Encoding utf8
  $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "artifact-manifest-preview.json") -Encoding utf8
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
  "safe-summary" { [pscustomobject]@{ ok = $true; upload_planned = $false; install_planned = $false; github_release_planned = $false; token_printed = $false } }
  "report" { Write-CandidateReports }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
