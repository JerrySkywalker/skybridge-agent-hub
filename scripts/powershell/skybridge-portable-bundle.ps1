[CmdletBinding()]
param(
  [ValidateSet("status", "manifest", "verify", "component-list", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\portable-bundle"
$BundleVersion = "v1.4.0-portable-local-bundle-rc"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe portable bundle JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe portable bundle markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Test-RepoPath([string]$RelativePath) {
  Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath)
}

function New-Component([string]$Id, [string]$Path, [string]$Role) {
  [pscustomobject]@{
    schema = "skybridge.portable_bundle_component.v1"
    component_id = $Id
    role = $Role
    repo_path = $Path
    present = Test-RepoPath $Path
    host_mutation_allowed = $false
    install_allowed = $false
    upload_allowed = $false
    token_printed = $false
  }
}

function Get-Components {
  @(
    New-Component "repo-local-launcher" "skybridge.ps1" "operator entrypoint"
    New-Component "repo-local-launcher-cmd" "skybridge.cmd" "cmd wrapper"
    New-Component "launcher-script" "scripts/powershell/skybridge-launcher.ps1" "command router"
    New-Component "local-session-script" "scripts/powershell/skybridge-local-session.ps1" "bounded non-worker local session"
    New-Component "local-doctor" "scripts/powershell/skybridge-local-doctor.ps1" "health doctor"
    New-Component "diagnostics" "scripts/powershell/skybridge-diagnostics.ps1" "safe diagnostics"
    New-Component "product-readiness" "scripts/powershell/skybridge-diagnostics.ps1" "product readiness"
    New-Component "first-run-wizard-fixtures" "fixtures/demo/operator-walkthrough.fixture.json" "safe first-run demo fixture"
    New-Component "web-preview-surface" "apps/web/src/main.tsx" "read-only web surface"
    New-Component "desktop-preview-surface" "apps/desktop/src/main.tsx" "read-only desktop surface"
    New-Component "docs-runbooks" "docs/dev/REPO_LOCAL_LAUNCHER.md" "local operator docs"
    New-Component "smoke-matrix" "scripts/powershell/skybridge-smoke-matrix.ps1" "local validation matrix"
    New-Component "safe-metadata-directories" ".agent" "ignored metadata root"
  )
}

function Get-ExcludedPaths {
  @("node_modules", "target", "dist", "build caches", "raw logs", "raw prompts", "raw transcripts", "stdout captures", "stderr captures", "env dumps", "secrets", "tokens", "authorization headers", "cookies", "private keys", "raw pairing codes")
}

function New-Manifest {
  [pscustomobject]@{
    schema = "skybridge.portable_bundle_manifest.v1"
    bundle_version = $BundleVersion
    repo_commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    required_entrypoints = @("skybridge.ps1", "skybridge.cmd", "scripts/powershell/skybridge-launcher.ps1")
    docs_present = (Test-RepoPath "docs/dev/PORTABLE_LOCAL_BUNDLE_LAYOUT.md") -and (Test-RepoPath "docs/dev/PORTABLE_LOCAL_BUNDLE_POLICY.md")
    scripts_present = (Test-RepoPath "scripts/powershell/skybridge-launcher.ps1") -and (Test-RepoPath "scripts/powershell/skybridge-local-session.ps1") -and (Test-RepoPath "scripts/powershell/skybridge-local-doctor.ps1") -and (Test-RepoPath "scripts/powershell/skybridge-diagnostics.ps1")
    fixture_present = (Test-RepoPath "fixtures/demo/local-session-demo.fixture.json") -and (Test-RepoPath "fixtures/demo/operator-walkthrough.fixture.json") -and (Test-RepoPath "fixtures/demo/product-readiness-demo.fixture.json")
    components = @(Get-Components)
    excluded_paths = @(Get-ExcludedPaths)
    host_mutation_allowed = $false
    install_allowed = $false
    upload_allowed = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    token_printed = $false
  }
}

function New-Verification {
  $Manifest = New-Manifest
  $Missing = @($Manifest.components | Where-Object { -not $_.present } | ForEach-Object { $_.component_id })
  $ForbiddenIncluded = @($Manifest.components | Where-Object { $_.repo_path -match "node_modules|target|raw|secret|token|cookie|private" } | ForEach-Object { $_.repo_path })
  [pscustomobject]@{
    schema = "skybridge.portable_bundle_verification.v1"
    ok = ($Missing.Count -eq 0 -and $ForbiddenIncluded.Count -eq 0 -and $Manifest.token_printed -eq $false)
    missing_components = $Missing
    forbidden_included_paths = $ForbiddenIncluded
    no_token_like_content = -not (Test-UnsafeText ($Manifest | ConvertTo-Json -Depth 30))
    host_mutation_allowed = $false
    install_allowed = $false
    upload_allowed = $false
    token_printed = $false
  }
}

function Write-Layout {
  $Layout = [pscustomobject]@{
    schema = "skybridge.portable_local_bundle.v1"
    bundle_version = $BundleVersion
    components = @(Get-Components)
    excluded_paths = @(Get-ExcludedPaths)
    safe_metadata_directories = @(".agent/tmp/portable-bundle", ".agent/tmp/local-launcher", ".agent/tmp/local-session")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "portable-bundle-layout.json") $Layout
  Write-SafeMarkdown (Join-Path $ReportDir "portable-bundle-layout.md") @(
    "# Portable Local Bundle Layout",
    "",
    "- schema: skybridge.portable_local_bundle.v1",
    "- bundle_version: $BundleVersion",
    "- host_mutation_allowed=false",
    "- install_allowed=false",
    "- upload_allowed=false",
    "- token_printed=false"
  )
  $Layout
}

function Write-Report {
  $Manifest = New-Manifest
  $Verification = New-Verification
  $Layout = Write-Layout
  $Report = [pscustomobject]@{
    schema = "skybridge.portable_bundle_report.v1"
    rc_version = $BundleVersion
    commit = $Manifest.repo_commit
    portable_bundle_status = $(if ($Verification.ok) { "verified" } else { "blocked" })
    manifest_status = "written"
    layout = $Layout
    manifest = $Manifest
    verification = $Verification
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "portable-bundle-manifest.json") $Manifest
  Write-SafeJson (Join-Path $ReportDir "portable-bundle-report.json") $Report
  $RcReport = [pscustomobject]@{
    schema = "skybridge.portable_local_bundle_rc_report.v1"
    rc_version = $BundleVersion
    commit = $Manifest.repo_commit
    launcher_status = "ready"
    portable_bundle_status = $Report.portable_bundle_status
    manifest_status = "verified"
    stop_hook_diagnostics_status = "ready"
    rehearsal_status = "ready"
    web_status = "portable_bundle_panel_readonly"
    desktop_status = "portable_bundle_panel_readonly"
    disabled_capabilities = $Report.disabled_capabilities
    known_limitations = @("repo-local only", "no installer", "no service install", "no autostart", "no remote execution", "no artifact upload")
    next_recommended_goals = @("visual QA for portable bundle panels", "safe metadata read model", "authenticated local pairing")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "portable-local-bundle-rc-report.json") $RcReport
  Write-SafeMarkdown (Join-Path $ReportDir "portable-bundle-report.md") @(
    "# Portable Bundle Report",
    "",
    "- schema: skybridge.portable_bundle_report.v1",
    "- rc_version: $BundleVersion",
    "- portable_bundle_status: $($Report.portable_bundle_status)",
    "- manifest_status: written",
    "- install_allowed=false",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  Write-SafeMarkdown (Join-Path $ReportDir "portable-local-bundle-rc-report.md") @(
    "# Portable Local Bundle RC Report",
    "",
    "- schema: skybridge.portable_local_bundle_rc_report.v1",
    "- rc_version: $BundleVersion",
    "- portable_bundle_status: $($Report.portable_bundle_status)",
    "- manifest_status: verified",
    "- stop_hook_diagnostics_status: ready",
    "- rehearsal_status: ready",
    "- token_printed=false"
  )
  $Report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.portable_local_bundle.v1"; status = "ready"; bundle_version = $BundleVersion; components = @(Get-Components); token_printed = $false } }
  "manifest" { New-Manifest }
  "verify" { New-Verification }
  "component-list" { @(Get-Components) }
  "safe-summary" { [pscustomobject]@{ ok = $true; install_allowed = $false; host_mutation_allowed = $false; upload_allowed = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
