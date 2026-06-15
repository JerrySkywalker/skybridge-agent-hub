[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "build-preview", "build-sandbox-candidate", "verify", "install-plan-preview", "uninstall-plan-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$WorkDir = Join-Path $RepoRoot ".agent\tmp\installer-candidate"
$DistDir = Join-Path $WorkDir "dist"
$StageRoot = Join-Path $WorkDir "stage\skybridge-agent-hub-installer-candidate"
$InstallRoot = Join-Path $WorkDir "install-root"
$CandidateVersion = "v1.8.0-sandboxed-installer-soak-rc"

function Assert-CandidatePath([string]$Path) {
  $root = [System.IO.Path]::GetFullPath($WorkDir)
  $target = [System.IO.Path]::GetFullPath($Path)
  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes installer candidate sandbox: $Path" }
}

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  Assert-CandidatePath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe installer candidate JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  Assert-CandidatePath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe installer candidate markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-IncludedFiles {
  @(
    "skybridge.ps1",
    "skybridge.cmd",
    "scripts/powershell/skybridge-launcher.ps1",
    "scripts/powershell/skybridge-local-session.ps1",
    "scripts/powershell/skybridge-local-doctor.ps1",
    "scripts/powershell/skybridge-diagnostics.ps1",
    "scripts/powershell/skybridge-smoke-matrix.ps1",
    "scripts/powershell/skybridge-portable-package.ps1",
    "scripts/powershell/skybridge-install-sandbox.ps1",
    "scripts/powershell/skybridge-installer-candidate.ps1",
    "docs/dev/REPO_LOCAL_LAUNCHER.md",
    "docs/dev/SANDBOXED_INSTALLER_CANDIDATE.md",
    "docs/dev/INSTALLER_MANIFEST_POLICY.md",
    "docs/dev/INSTALLER_HOST_MUTATION_BOUNDARY.md"
  )
}

function Get-Plan {
  [pscustomobject]@{
    schema = "skybridge.installer_plan.v1"
    candidate_version = $CandidateVersion
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    candidate_root_sanitized = ".agent/tmp/installer-candidate"
    staged_root_sanitized = ".agent/tmp/installer-candidate/stage/skybridge-agent-hub-installer-candidate"
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    dist_root_sanitized = ".agent/tmp/installer-candidate/dist"
    source_package = "repo-local staged candidate"
    included_files = @(Get-IncludedFiles)
    build_writes_only_agent_tmp = $true
    installer_is_host_installer = $false
    host_mutation_allowed = $false
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    powercfg_allowed = $false
    path_write_allowed = $false
    upload_allowed = $false
    github_release_allowed = $false
    token_printed = $false
  }
}

function Copy-IncludedFiles {
  if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
  foreach ($relative in Get-IncludedFiles) {
    if ($relative -match "(^|/)(\.git|node_modules|target|dist|build|coverage|\.agent)(/|$)|(^|/)\.env|secret|token|cookie|\.log$") { throw "Forbidden installer candidate path: $relative" }
    $source = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing installer candidate source: $relative" }
    $dest = Join-Path $StageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
  }
}

function Get-DirSummary([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ exists = $false; file_count = 0; size_bytes = 0; token_printed = $false } }
  $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File)
  [pscustomobject]@{ exists = $true; file_count = $files.Count; size_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum ?? 0); token_printed = $false }
}

function Build-Candidate([switch]$Archive) {
  Copy-IncludedFiles
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  $bundle = Join-Path $DistDir "skybridge-agent-hub-installer-candidate-v1.8.0.zip"
  $exists = $false
  if ($Archive -and (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath $bundle) { Remove-Item -LiteralPath $bundle -Force }
    Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $bundle -Force
    $exists = $true
  }
  [pscustomobject]@{
    schema = "skybridge.installer_candidate.v1"
    candidate_version = $CandidateVersion
    staged_root_sanitized = ".agent/tmp/installer-candidate/stage/skybridge-agent-hub-installer-candidate"
    bundle_path_sanitized = $(if ($exists) { ".agent/tmp/installer-candidate/dist/skybridge-agent-hub-installer-candidate-v1.8.0.zip" } else { $null })
    bundle_exists = $exists
    stage = Get-DirSummary $StageRoot
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Get-Manifest {
  $stageFiles = if (Test-Path -LiteralPath $StageRoot) { @(Get-ChildItem -LiteralPath $StageRoot -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($StageRoot, $_.FullName).Replace("\", "/") } | Sort-Object) } else { @() }
  [pscustomobject]@{
    schema = "skybridge.installer_manifest.v1"
    candidate_version = $CandidateVersion
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    source_package = "repo-local staged candidate"
    staged_root_sanitized = ".agent/tmp/installer-candidate/stage/skybridge-agent-hub-installer-candidate"
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    entrypoints = @("skybridge.ps1", "skybridge.cmd", "scripts/powershell/skybridge-launcher.ps1")
    docs_runbooks = @("docs/dev/SANDBOXED_INSTALLER_CANDIDATE.md", "docs/dev/INSTALLER_MANIFEST_POLICY.md", "docs/dev/INSTALLER_HOST_MUTATION_BOUNDARY.md")
    file_count = $stageFiles.Count
    files_preview = @($stageFiles | Select-Object -First 50)
    forbidden_paths_absent = (@($stageFiles | Where-Object { $_ -match "(^|/)(\.git|node_modules|target|dist|build|coverage|\.agent)(/|$)|(^|/)\.env|secret|token|cookie|\.log$" }).Count -eq 0)
    host_mutation_allowed = $false
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    powercfg_allowed = $false
    upload_allowed = $false
    github_release_allowed = $false
    token_printed = $false
  }
}

function Install-PlanPreview {
  [pscustomobject]@{
    schema = "skybridge.installer_plan.v1"
    action = "install-plan-preview"
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    would_copy_stage_to_install_root = $true
    writes_outside_agent_tmp = $false
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    powercfg_allowed = $false
    path_write_allowed = $false
    token_printed = $false
  }
}

function Uninstall-PlanPreview {
  [pscustomobject]@{
    schema = "skybridge.installer_plan.v1"
    action = "uninstall-plan-preview"
    delete_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    deletes_outside_agent_tmp = $false
    host_uninstall_allowed = $false
    token_printed = $false
  }
}

function Invoke-InstallRoot {
  if (-not (Test-Path -LiteralPath $StageRoot)) { Build-Candidate | Out-Null }
  if (Test-Path -LiteralPath $InstallRoot) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  Copy-Item -Path (Join-Path $StageRoot "*") -Destination $InstallRoot -Recurse -Force
}

function Verify-Candidate {
  Invoke-InstallRoot
  $manifest = Get-Manifest
  $required = @("skybridge.ps1", "skybridge.cmd", "scripts/powershell/skybridge-launcher.ps1", "scripts/powershell/skybridge-local-doctor.ps1")
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $InstallRoot $_)) })
  $verification = [pscustomobject]@{
    schema = "skybridge.installer_verification.v1"
    ok = ($missing.Count -eq 0 -and $manifest.forbidden_paths_absent)
    candidate_version = $CandidateVersion
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    missing_required_paths = $missing
    forbidden_paths_absent = $manifest.forbidden_paths_absent
    install_plan = Install-PlanPreview
    uninstall_plan = Uninstall-PlanPreview
    host_mutation_allowed = $false
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    powercfg_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "installer-verification.json") $verification
  $verification
}

function Write-Report {
  $candidate = Build-Candidate -Archive
  $manifest = Get-Manifest
  $verification = Verify-Candidate
  $report = [pscustomobject]@{
    schema = "skybridge.installer_report.v1"
    status = $(if ($verification.ok) { "passed" } else { "blocked" })
    candidate = $candidate
    manifest = $manifest
    verification = $verification
    disabled_capabilities = @("host_install", "host_uninstall", "registry", "startup", "scheduled_task", "service", "powercfg", "PATH", "upload", "github_release", "codex_worker", "workunit_apply", "task_claim", "queue_apply")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "installer-plan.json") (Get-Plan)
  Write-SafeJson (Join-Path $WorkDir "installer-manifest.json") $manifest
  Write-SafeJson (Join-Path $WorkDir "installer-report.json") $report
  Write-SafeMarkdown (Join-Path $WorkDir "installer-report.md") @(
    "# Sandboxed Installer Candidate Report",
    "",
    "- schema: skybridge.installer_report.v1",
    "- status: $($report.status)",
    "- candidate_version: $CandidateVersion",
    "- install_root: .agent/tmp/installer-candidate/install-root",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.installer_candidate.v1"; status = "ready"; candidate_version = $CandidateVersion; candidate_root_sanitized = ".agent/tmp/installer-candidate"; token_printed = $false } }
  "plan" { $p = Get-Plan; Write-SafeJson (Join-Path $WorkDir "installer-plan.json") $p; $p }
  "build-preview" { Build-Candidate }
  "build-sandbox-candidate" { Build-Candidate -Archive }
  "verify" { Verify-Candidate }
  "install-plan-preview" { Install-PlanPreview }
  "uninstall-plan-preview" { Uninstall-PlanPreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; writes_only_agent_tmp = $true; host_mutation_allowed = $false; registry_write_allowed = $false; startup_write_allowed = $false; scheduled_task_allowed = $false; service_install_allowed = $false; powercfg_allowed = $false; upload_allowed = $false; github_release_allowed = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
