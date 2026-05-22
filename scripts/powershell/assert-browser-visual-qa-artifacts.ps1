[CmdletBinding()]
param(
  [string]$ArtifactDir = ".agent/tmp/browser-visual-qa"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ArtifactDir)) {
  Write-Host "Browser visual QA artifact directory is absent; nothing to validate."
  exit 0
}

$manifestPath = Join-Path $ArtifactDir "manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Browser visual QA artifacts exist without manifest.json."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if ($manifest.fixture_only -ne $true) {
  throw "Browser visual QA manifest is not marked fixture_only."
}

if ($manifest.production_endpoint_used -ne $false) {
  throw "Browser visual QA manifest indicates production endpoint usage."
}

if (-not $manifest.web_base_origin) {
  throw "Browser visual QA manifest is missing web_base_origin."
}

$origin = [Uri]$manifest.web_base_origin
$loopbackHosts = @("127.0.0.1", "localhost", "::1", "[::1]")
if ($loopbackHosts -notcontains $origin.Host) {
  throw "Browser visual QA manifest web_base_origin is not loopback: $($manifest.web_base_origin)"
}

if (-not $manifest.screenshots -or $manifest.screenshots.Count -lt 1) {
  throw "Browser visual QA manifest does not list screenshots."
}

foreach ($screenshot in $manifest.screenshots) {
  if (-not $screenshot.file) {
    throw "Browser visual QA manifest contains a screenshot entry without a file."
  }

  $filePath = Join-Path $ArtifactDir $screenshot.file
  if (-not (Test-Path -LiteralPath $filePath)) {
    throw "Browser visual QA screenshot is missing: $($screenshot.file)"
  }

  if ([System.IO.Path]::GetExtension($filePath) -ne ".png") {
    throw "Browser visual QA screenshot is not a PNG: $($screenshot.file)"
  }
}

Write-Host "Browser visual QA artifacts are fixture-only and safe to upload."
