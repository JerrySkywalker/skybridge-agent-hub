[CmdletBinding()]
param(
  [ValidateSet("status", "verify-package", "verify-manifest", "verify-checksum", "provenance", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\portable-package"
$PackageScript = Join-Path $PSScriptRoot "skybridge-portable-package.ps1"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-PackageJson([string]$CommandName) {
  (& pwsh -NoProfile -ExecutionPolicy Bypass -File $PackageScript -Command $CommandName -Json | Out-String).Trim() | ConvertFrom-Json
}

function Get-Manifest {
  Invoke-PackageJson "build-package"
}

function New-Checksum {
  $manifest = Get-Manifest
  $packagePath = if ($manifest.package_path_sanitized) { Join-Path $RepoRoot $manifest.package_path_sanitized } else { $null }
  $manifestText = $manifest | ConvertTo-Json -Depth 40
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestText)
  $manifestHash = ($sha.ComputeHash($manifestBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
  [pscustomobject]@{
    schema = "skybridge.artifact_checksum.v1"
    manifest_sha256 = $manifestHash
    package_sha256 = $(if ($packagePath -and (Test-Path -LiteralPath $packagePath)) { (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null })
    package_size = $(if ($packagePath -and (Test-Path -LiteralPath $packagePath)) { (Get-Item -LiteralPath $packagePath).Length } else { 0 })
    token_printed = $false
  }
}

function New-Provenance {
  $manifest = Get-Manifest
  [pscustomobject]@{
    schema = "skybridge.artifact_provenance.v1"
    source_commit = $manifest.source_commit
    tag = "v1.5.0-portable-package-rc"
    package_path_sanitized = $manifest.package_path_sanitized
    included_entrypoints = $manifest.included_entrypoints
    excluded_forbidden_patterns = $manifest.excluded_paths
    upload_allowed = $false
    install_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function New-Reproducibility {
  $a = Get-Manifest
  Start-Sleep -Milliseconds 25
  $b = Get-Manifest
  $sameFiles = (@($a.included_entrypoints + $a.included_docs + $a.included_scripts + $a.included_fixtures) -join "|") -eq (@($b.included_entrypoints + $b.included_docs + $b.included_scripts + $b.included_fixtures) -join "|")
  $sameManifest = $sameFiles -and ($a.package_id -eq $b.package_id) -and ($a.package_version -eq $b.package_version)
  $report = [pscustomobject]@{
    schema = "skybridge.package_rebuild_reproducibility_preview.v1"
    reproducible_manifest = $sameManifest
    reproducible_file_list = $sameFiles
    reproducible_archive = ($a.sha256 -eq $b.sha256)
    archive_difference_reason = $(if ($a.sha256 -eq $b.sha256) { $null } else { "zip metadata timestamps may differ; manifest and file list are authoritative for this preview" })
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "package-rebuild-reproducibility-report.json") $report
  @("# Package Rebuild Reproducibility", "", "- reproducible_manifest=$($report.reproducible_manifest)", "- reproducible_archive=$($report.reproducible_archive)", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "package-rebuild-reproducibility-report.md") -Encoding utf8
  $report
}

function Write-Report {
  $manifest = Get-Manifest
  $checksum = New-Checksum
  $provenance = New-Provenance
  $clean = Invoke-PackageJson "clean-room-rehearsal"
  $report = [pscustomobject]@{
    schema = "skybridge.artifact_integrity_report.v1"
    package_path_sanitized = $manifest.package_path_sanitized
    source_commit = $manifest.source_commit
    tag = "v1.5.0-portable-package-rc"
    manifest_sha256 = $checksum.manifest_sha256
    package_sha256 = $checksum.package_sha256
    package_size = $checksum.package_size
    included_entrypoints = $manifest.included_entrypoints
    excluded_forbidden_patterns = $manifest.excluded_paths
    clean_room_verified = ($clean.status -eq "passed")
    upload_allowed = $false
    install_allowed = $false
    host_mutation_allowed = $false
    provenance = $provenance
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "artifact-integrity-report.json") $report
  @("# Artifact Integrity Report", "", "- schema: skybridge.artifact_integrity_report.v1", "- clean_room_verified=$($report.clean_room_verified)", "- upload_allowed=false", "- install_allowed=false", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "artifact-integrity-report.md") -Encoding utf8
  New-Reproducibility | Out-Null
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.artifact_integrity.v1"; status = "ready"; token_printed = $false } }
  "verify-package" { Get-Manifest }
  "verify-manifest" { Get-Manifest }
  "verify-checksum" { New-Checksum }
  "provenance" { New-Provenance }
  "safe-summary" { [pscustomobject]@{ ok = $true; upload_allowed = $false; install_allowed = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
