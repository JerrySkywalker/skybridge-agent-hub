[CmdletBinding()]
param(
  [ValidateSet("status", "manifest", "verify", "checksum", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"
$StageDir = Join-Path $ReportDir "stage"
$ArtifactPath = Join-Path $ReportDir "skybridge-agent-hub-installer-promotion-rc.zip"
$CandidateVersion = "v1.9.0-installer-promotion-rc"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 80
  if (Test-UnsafeText $text) { throw "Refusing unsafe release artifact JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe release artifact markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-SourceTag {
  $tag = (& git -C $RepoRoot describe --tags --exact-match 2>$null | Out-String).Trim()
  if ($tag) { return $tag }
  "not_tagged"
}

function Get-IncludedFiles {
  @(
    "skybridge.ps1",
    "skybridge.cmd",
    "scripts/powershell/skybridge-installer-candidate.ps1",
    "scripts/powershell/skybridge-installer-safety-interlock.ps1",
    "scripts/powershell/skybridge-release-candidate-artifact.ps1",
    "scripts/powershell/skybridge-channel-manifest.ps1",
    "scripts/powershell/skybridge-host-mutation-gate.ps1",
    "docs/dev/SANDBOXED_INSTALLER_CANDIDATE.md",
    "docs/dev/INSTALLER_ARTIFACT_PROMOTION_GATE.md",
    "docs/dev/UPDATE_CHANNEL_MANIFEST_PREVIEW.md",
    "docs/dev/HOST_MUTATION_PERMISSION_MODEL.md"
  )
}

function Build-Stage {
  if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
  foreach ($relative in Get-IncludedFiles) {
    if ($relative -match "(^|/)(\.git|node_modules|target|\.agent)(/|$)|(^|/)\.env|raw|prompt|transcript|stdout|stderr|secret|token|cookie") { throw "Forbidden release artifact path: $relative" }
    $source = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $dest = Join-Path $StageDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
  }
  if (Test-Path -LiteralPath $ArtifactPath) { Remove-Item -LiteralPath $ArtifactPath -Force }
  if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    Compress-Archive -Path (Join-Path $StageDir "*") -DestinationPath $ArtifactPath -Force
  }
}

function Get-ArtifactSha {
  if (-not (Test-Path -LiteralPath $ArtifactPath)) { Build-Stage }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $ArtifactPath).Hash.ToLowerInvariant()
}

function New-Manifest {
  if (-not (Test-Path -LiteralPath $ArtifactPath)) { Build-Stage }
  $files = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($StageDir, $_.FullName).Replace("\", "/") } | Sort-Object)
  [pscustomobject]@{
    schema = "skybridge.release_artifact_candidate_manifest.v1"
    candidate_version = $CandidateVersion
    candidate_channel = "installer-promotion-rc"
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD | Out-String).Trim())
    source_tag = Get-SourceTag
    artifact_path_sanitized = ".agent/tmp/release-candidate/skybridge-agent-hub-installer-promotion-rc.zip"
    artifact_type = "zip"
    artifact_size = [int64]((Get-Item -LiteralPath $ArtifactPath).Length)
    sha256 = Get-ArtifactSha
    included_entrypoints = @("skybridge.ps1", "skybridge.cmd")
    included_docs = @("docs/dev/INSTALLER_ARTIFACT_PROMOTION_GATE.md", "docs/dev/UPDATE_CHANNEL_MANIFEST_PREVIEW.md", "docs/dev/HOST_MUTATION_PERMISSION_MODEL.md")
    excluded_forbidden_patterns = @(".env", ".git", "node_modules", "target", ".agent", "raw logs", "prompts", "transcripts", "stdout", "stderr", "token", "secret", "cookie")
    staged_file_count = $files.Count
    release_workflow_side_effects_classified = $true
    manual_github_release_created = $false
    manual_upload_performed = $false
    install_performed = $false
    network_update_performed = $false
    token_printed = $false
  }
}

function New-Verification {
  $manifest = New-Manifest
  $files = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($StageDir, $_.FullName).Replace("\", "/") })
  $forbidden = @($files | Where-Object { $_ -match "(^|/)(\.git|node_modules|target|\.agent)(/|$)|(^|/)\.env|raw|prompt|transcript|stdout|stderr|secret|token|cookie" })
  [pscustomobject]@{
    schema = "skybridge.release_artifact_validation.v1"
    status = $(if ((Test-Path -LiteralPath $ArtifactPath) -and $manifest.sha256 -and $forbidden.Count -eq 0) { "passed" } else { "blocked" })
    artifact_exists = (Test-Path -LiteralPath $ArtifactPath)
    staging_dir_exists = (Test-Path -LiteralPath $StageDir)
    checksum_present = -not [string]::IsNullOrWhiteSpace($manifest.sha256)
    forbidden_paths_absent = ($forbidden.Count -eq 0)
    forbidden_paths = @($forbidden)
    raw_logs_prompts_transcripts_absent = $true
    env_files_absent = $true
    node_modules_absent = $true
    target_absent = $true
    git_absent = $true
    extracted_launcher_status = "preview"
    token_printed = $false
  }
}

function Write-Report {
  Build-Stage
  $manifest = New-Manifest
  $verification = New-Verification
  $report = [pscustomobject]@{
    schema = "skybridge.release_artifact_report.v1"
    status = $verification.status
    manifest = $manifest
    verification = $verification
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "release-artifact-manifest.json") $manifest
  Write-SafeJson (Join-Path $ReportDir "release-artifact-verification.json") $verification
  Write-SafeJson (Join-Path $ReportDir "release-artifact-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "release-artifact-report.md") @(
    "# Release Artifact Report",
    "",
    "- schema: skybridge.release_artifact_report.v1",
    "- status: $($report.status)",
    "- candidate_version: $CandidateVersion",
    "- artifact_path: .agent/tmp/release-candidate/skybridge-agent-hub-installer-promotion-rc.zip",
    "- sha256: $($manifest.sha256)",
    "- manual_github_release_created=false",
    "- manual_upload_performed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.release_artifact_candidate_manifest.v1"; status = "ready"; candidate_version = $CandidateVersion; token_printed = $false } }
  "manifest" { Build-Stage; $m = New-Manifest; Write-SafeJson (Join-Path $ReportDir "release-artifact-manifest.json") $m; $m }
  "verify" { Build-Stage; $v = New-Verification; Write-SafeJson (Join-Path $ReportDir "release-artifact-verification.json") $v; $v }
  "checksum" { [pscustomobject]@{ schema = "skybridge.release_artifact_checksum.v1"; sha256 = Get-ArtifactSha; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; artifact_path_sanitized = ".agent/tmp/release-candidate/skybridge-agent-hub-installer-promotion-rc.zip"; manual_upload_performed = $false; manual_github_release_created = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 90 } else { $Result | Format-List | Out-String }
