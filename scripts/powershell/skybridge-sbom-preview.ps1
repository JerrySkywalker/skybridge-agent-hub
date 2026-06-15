[CmdletBinding()]
param(
  [ValidateSet("status", "dependency-inventory", "license-summary", "package-summary", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\sbom"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|environment dump|env_dump|raw_ci_log|raw_worker_log|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 90
  if (Test-UnsafeText $text) { throw "Refusing unsafe SBOM JSON: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe SBOM markdown: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Read-PackageJson([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-PackageInventory {
  $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter package.json |
    Where-Object { $_.FullName -notmatch "\\node_modules\\|\\dist\\|\\build\\|\\target\\" }
  $items = @()
  foreach ($file in $files) {
    $pkg = Read-PackageJson $file.FullName
    if ($null -eq $pkg) { continue }
    $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $file.FullName).Replace("\", "/")
    $deps = @()
    if ($pkg.dependencies) {
      foreach ($prop in $pkg.dependencies.PSObject.Properties) {
        $deps += [pscustomobject]@{ name = $prop.Name; specifier = [string]$prop.Value; dependency_type = "runtime" }
      }
    }
    if ($pkg.devDependencies) {
      foreach ($prop in $pkg.devDependencies.PSObject.Properties) {
        $deps += [pscustomobject]@{ name = $prop.Name; specifier = [string]$prop.Value; dependency_type = "dev" }
      }
    }
    $items += [pscustomobject]@{
      package_name = if ($pkg.name) { [string]$pkg.name } else { $rel }
      version = if ($pkg.version) { [string]$pkg.version } else { "not_declared" }
      package_file = $rel
      dependency_count = @($deps).Count
      dependencies = $deps
    }
  }
  return $items
}

function New-DependencyInventory {
  $packages = Get-PackageInventory
  [pscustomobject]@{
    schema = "skybridge.dependency_inventory.v1"
    generated_from = "local package.json files"
    network_used = $false
    package_install_performed = $false
    package_count = @($packages).Count
    dependency_count = @($packages | ForEach-Object { $_.dependency_count } | Measure-Object -Sum).Sum
    packages = $packages
    token_printed = $false
  }
}

function New-LicenseSummary {
  [pscustomobject]@{
    schema = "skybridge.license_summary.v1"
    source = "package metadata preview"
    network_used = $false
    license_resolution = "not_resolved_without_network"
    known_project_license = "MIT"
    unresolved_dependency_license_count = (New-DependencyInventory).dependency_count
    token_printed = $false
  }
}

function New-Sbom {
  $inventory = New-DependencyInventory
  [pscustomobject]@{
    schema = "skybridge.sbom_preview.v1"
    preview_only = $true
    format = "safe-metadata-preview"
    upload_performed = $false
    network_used = $false
    package_install_performed = $false
    environment_dump_persisted = $false
    dependency_inventory = $inventory
    token_printed = $false
  }
}

function New-Report {
  $sbom = New-Sbom
  $inventory = $sbom.dependency_inventory
  $license = New-LicenseSummary
  Write-SafeJson (Join-Path $ReportDir "sbom-preview.json") $sbom
  Write-SafeJson (Join-Path $ReportDir "dependency-inventory.json") $inventory
  Write-SafeJson (Join-Path $ReportDir "license-summary.json") $license
  Write-SafeMarkdown (Join-Path $ReportDir "sbom-report.md") @(
    "# SBOM Preview Report",
    "",
    "- status: ready",
    "- schema: skybridge.sbom_preview.v1",
    "- package_count: $($inventory.package_count)",
    "- dependency_count: $($inventory.dependency_count)",
    "- network_used: false",
    "- package_install_performed: false",
    "- upload_performed: false",
    "- environment_dump_persisted: false",
    "- token_printed=false"
  )
  return [pscustomobject]@{
    schema = "skybridge.sbom_preview_report.v1"
    status = "ready"
    sbom = $sbom
    dependency_inventory = $inventory
    license_summary = $license
    token_printed = $false
  }
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.sbom_preview.v1"; status = "ready"; network_used = $false; token_printed = $false } }
  "dependency-inventory" { New-DependencyInventory }
  "license-summary" { New-LicenseSummary }
  "package-summary" { [pscustomobject]@{ schema = "skybridge.package_summary.v1"; packages = @(Get-PackageInventory | Select-Object package_name, version, dependency_count); token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; network_used = $false; package_install_performed = $false; upload_performed = $false; environment_dump_persisted = $false; token_printed = $false } }
  "report" { New-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
