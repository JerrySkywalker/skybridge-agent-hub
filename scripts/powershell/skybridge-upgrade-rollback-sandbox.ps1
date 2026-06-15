[CmdletBinding()]
param(
  [ValidateSet("status", "upgrade-plan", "upgrade-sandbox", "rollback-plan", "rollback-sandbox", "verify", "safe-summary", "report", "migration-preview")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SandboxRoot = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
$CurrentRoot = Join-Path $SandboxRoot "current"
$PreviousRoot = Join-Path $SandboxRoot "previous"
$RollbackRoot = Join-Path $SandboxRoot "rollback"
$StagingRoot = Join-Path $SandboxRoot "staging"
$PackagePath = Join-Path $RepoRoot ".agent\tmp\portable-package\dist\skybridge-agent-hub-portable-v1.5.0.zip"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Assert-UnderSandbox([string]$Path) {
  $root = [System.IO.Path]::GetFullPath($SandboxRoot)
  $target = [System.IO.Path]::GetFullPath($Path)
  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes install sandbox: $Path" }
}

function Write-SafeJson([string]$Path, $Value) {
  Assert-UnderSandbox $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 50
  if (Test-UnsafeText $text) { throw "Refusing unsafe upgrade rollback JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  Assert-UnderSandbox $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe upgrade rollback markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-DirSummary([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ exists = $false; file_count = 0; size_bytes = 0; token_printed = $false }
  }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File)
  [pscustomobject]@{ exists = $true; file_count = $files.Count; size_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum ?? 0); token_printed = $false }
}

function Get-MigrationPreview {
  [pscustomobject]@{
    schema = "skybridge.sandbox_migration_report.v1"
    status = "preview"
    from_version = "v1.5.0-portable-package-rc"
    to_version = "v1.6.0-clean-room-portable-acceptance-rc"
    channel = "local"
    network_update = $false
    github_release = $false
    binary_download = $false
    package_path_sanitized = ".agent/tmp/portable-package/dist/skybridge-agent-hub-portable-v1.5.0.zip"
    migration_steps = @("snapshot current to previous", "stage package under install sandbox", "replace current from staging", "preserve previous for rollback")
    token_printed = $false
  }
}

function Get-UpgradePlan {
  [pscustomobject]@{
    schema = "skybridge.sandbox_upgrade_plan.v1"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox"
    current = Get-DirSummary $CurrentRoot
    previous = Get-DirSummary $PreviousRoot
    staging = Get-DirSummary $StagingRoot
    package_exists = Test-Path -LiteralPath $PackagePath
    writes_only_under_install_sandbox = $true
    network_update = $false
    host_mutation_allowed = $false
    migration_preview = Get-MigrationPreview
    token_printed = $false
  }
}

function Get-RollbackPlan {
  [pscustomobject]@{
    schema = "skybridge.sandbox_rollback_plan.v1"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox"
    previous_available = Test-Path -LiteralPath $PreviousRoot
    current = Get-DirSummary $CurrentRoot
    previous = Get-DirSummary $PreviousRoot
    rollback = Get-DirSummary $RollbackRoot
    writes_only_under_install_sandbox = $true
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Copy-Directory([string]$Source, [string]$Destination) {
  Assert-UnderSandbox $Destination
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  if (Test-Path -LiteralPath $Source) {
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
      Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
  }
}

function Invoke-Upgrade {
  if (-not (Test-Path -LiteralPath $PackagePath)) { throw "Portable package artifact not found." }
  if (Test-Path -LiteralPath $CurrentRoot) { Copy-Directory $CurrentRoot $PreviousRoot }
  if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null
  Expand-Archive -LiteralPath $PackagePath -DestinationPath $StagingRoot -Force
  Copy-Directory $StagingRoot $CurrentRoot
  $report = [pscustomobject]@{
    schema = "skybridge.sandbox_migration_report.v1"
    status = "upgraded"
    upgrade_plan = Get-UpgradePlan
    current = Get-DirSummary $CurrentRoot
    previous = Get-DirSummary $PreviousRoot
    staging = Get-DirSummary $StagingRoot
    writes_only_under_install_sandbox = $true
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "upgrade-sandbox-report.json") $report
  $report
}

function Invoke-Rollback {
  if (-not (Test-Path -LiteralPath $PreviousRoot)) { throw "Previous sandbox snapshot not found." }
  if (Test-Path -LiteralPath $CurrentRoot) { Copy-Directory $CurrentRoot $RollbackRoot }
  Copy-Directory $PreviousRoot $CurrentRoot
  $report = [pscustomobject]@{
    schema = "skybridge.sandbox_migration_report.v1"
    status = "rolled_back"
    rollback_plan = Get-RollbackPlan
    current = Get-DirSummary $CurrentRoot
    previous = Get-DirSummary $PreviousRoot
    rollback = Get-DirSummary $RollbackRoot
    writes_only_under_install_sandbox = $true
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "rollback-sandbox-report.json") $report
  $report
}

function Invoke-Verify {
  [pscustomobject]@{
    schema = "skybridge.sandbox_migration_report.v1"
    status = if ((Test-Path -LiteralPath (Join-Path $CurrentRoot "skybridge.ps1")) -and (Test-Path -LiteralPath (Join-Path $PreviousRoot "skybridge.ps1"))) { "passed" } else { "preview" }
    current = Get-DirSummary $CurrentRoot
    previous = Get-DirSummary $PreviousRoot
    rollback = Get-DirSummary $RollbackRoot
    staging = Get-DirSummary $StagingRoot
    current_launcher_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "scripts\powershell\skybridge-launcher.ps1")
    writes_only_under_install_sandbox = $true
    network_update = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $upgrade = if (Test-Path -LiteralPath (Join-Path $SandboxRoot "upgrade-sandbox-report.json")) { Get-Content -Raw -LiteralPath (Join-Path $SandboxRoot "upgrade-sandbox-report.json") | ConvertFrom-Json } else { $null }
  $rollback = if (Test-Path -LiteralPath (Join-Path $SandboxRoot "rollback-sandbox-report.json")) { Get-Content -Raw -LiteralPath (Join-Path $SandboxRoot "rollback-sandbox-report.json") | ConvertFrom-Json } else { $null }
  $report = [pscustomobject]@{
    schema = "skybridge.sandbox_migration_report.v1"
    status = "reported"
    upgrade_plan = Get-UpgradePlan
    rollback_plan = Get-RollbackPlan
    migration_preview = Get-MigrationPreview
    upgrade_report = $upgrade
    rollback_report = $rollback
    verification = Invoke-Verify
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "version-channel-migration-preview.json") $report.migration_preview
  Write-SafeMarkdown (Join-Path $SandboxRoot "upgrade-rollback-sandbox-report.md") @(
    "# Upgrade Rollback Sandbox Report",
    "",
    "- schema: skybridge.sandbox_migration_report.v1",
    "- migration: v1.5.0-portable-package-rc to v1.6.0-clean-room-portable-acceptance-rc",
    "- channel: local",
    "- network_update=false",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.sandbox_migration_report.v1"; status = "ready"; current = Get-DirSummary $CurrentRoot; previous = Get-DirSummary $PreviousRoot; token_printed = $false } }
  "upgrade-plan" { $p = Get-UpgradePlan; Write-SafeJson (Join-Path $SandboxRoot "upgrade-sandbox-plan.json") $p; $p }
  "upgrade-sandbox" { Invoke-Upgrade }
  "rollback-plan" { $p = Get-RollbackPlan; Write-SafeJson (Join-Path $SandboxRoot "rollback-sandbox-plan.json") $p; $p }
  "rollback-sandbox" { Invoke-Rollback }
  "verify" { Invoke-Verify }
  "migration-preview" { Get-MigrationPreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; writes_only_under_install_sandbox = $true; network_update = $false; github_release = $false; binary_download = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 60 } else { $Result | Format-List | Out-String }
