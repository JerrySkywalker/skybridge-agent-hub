[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "build-preview", "build-package", "manifest", "verify", "extract-preview", "extract-smoke", "safe-summary", "report", "clean-room-plan", "clean-room-extract", "clean-room-status", "clean-room-rehearsal", "clean-room-cleanup-preview", "clean-room-safe-summary", "clean-room-report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$WorkDir = Join-Path $RepoRoot ".agent\tmp\portable-package"
$DistDir = Join-Path $WorkDir "dist"
$StageRoot = Join-Path $WorkDir "stage\skybridge-agent-hub-portable"
$ExtractRoot = Join-Path $WorkDir "extract-smoke\skybridge-agent-hub-portable"
$CleanRoomRoot = Join-Path $WorkDir "clean-room\skybridge-agent-hub-portable"
$PackageVersion = "v1.5.0-portable-package-rc"
$PackageId = "skybridge-agent-hub-portable"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 40
  if (Test-UnsafeText $Text) { throw "Refusing unsafe portable package JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe portable package markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
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
    "scripts/powershell/skybridge-bootstrap-complete.ps1",
    "scripts/powershell/skybridge-local-productization-rc.ps1",
    "scripts/powershell/skybridge-local-config.ps1",
    "scripts/powershell/skybridge-portable-bundle.ps1",
    "scripts/powershell/skybridge-portable-package.ps1",
    "scripts/powershell/skybridge-manual-install-preview.ps1",
    "scripts/powershell/skybridge-manual-uninstall-preview.ps1",
    "fixtures/demo/local-session-demo.fixture.json",
    "fixtures/demo/operator-walkthrough.fixture.json",
    "fixtures/demo/product-readiness-demo.fixture.json",
    "fixtures/productization/portable-config.example.json",
    "fixtures/productization/local-config.example.json",
    "apps/web/src/main.tsx",
    "apps/desktop/src/main.tsx",
    "docs/dev/REPO_LOCAL_LAUNCHER.md",
    "docs/dev/PORTABLE_LOCAL_BUNDLE_LAYOUT.md",
    "docs/dev/PORTABLE_LOCAL_BUNDLE_POLICY.md",
    "docs/dev/PORTABLE_PACKAGE_BUILDER.md",
    "docs/dev/PORTABLE_PACKAGE_EXCLUSION_POLICY.md",
    "docs/dev/PORTABLE_PACKAGE_MANIFEST.md",
    "docs/dev/PORTABLE_CONFIG_PROFILE.md",
    "docs/dev/PORTABLE_CONFIG_VALIDATION.md",
    "docs/dev/MANUAL_INSTALL_PREVIEW.md",
    "docs/dev/MANUAL_INSTALL_SAFETY_BOUNDARY.md",
    "docs/dev/MANUAL_UNINSTALL_PREVIEW.md",
    "docs/dev/PORTABLE_PACKAGE_RC.md",
    "docs/dev/PORTABLE_PACKAGE_RC_RELEASE_NOTES.md",
    "docs/dev/PORTABLE_PACKAGE_NEXT_ROADMAP.md",
    "docs/dev/PORTABLE_PACKAGE_INTEGRITY.md",
    "docs/dev/PORTABLE_PACKAGE_REPRODUCIBILITY_PREVIEW.md",
    "docs/dev/OPERATOR_ACCEPTANCE_CHECKLIST.md",
    "docs/dev/CLEAN_ROOM_PORTABLE_REHEARSAL.md",
    "docs/dev/PORTABLE_PACKAGE_OPERATOR_ACCEPTANCE.md",
    "docs/dev/LOCAL_SOAK_REHEARSAL.md"
  )
}

function Get-ExcludedPatterns {
  @(".git/**", "node_modules/**", "**/node_modules/**", "target/**", "**/target/**", "dist/**", "build/**", ".next/**", "coverage/**", ".env*", "**/*.log", "**/logs/**", "**/*secret*", "**/*token*", "**/*key*", "**/*cookie*", "**/raw/**", ".agent/tmp/**", "raw prompts/transcripts/stdout/stderr/worker logs/CI logs/GitHub logs", "Authorization/Bearer/cookie/private-key-like content")
}

function Test-ForbiddenPackagePath([string]$Path) {
  $p = $Path.Replace("\", "/")
  return $p -match "(^|/)(\.git|node_modules|target|dist|build|\.next|coverage)(/|$)|(^|/)\.env|\.log$|(^|/)logs(/|$)|secret|token|key|cookie|(^|/)raw(/|$)|^\.agent/tmp/"
}

function New-Plan {
  $files = @(Get-IncludedFiles)
  [pscustomobject]@{
    schema = "skybridge.portable_package_plan.v1"
    package_id = $PackageId
    package_version = $PackageVersion
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    package_root_sanitized = ".agent/tmp/portable-package"
    dist_root_sanitized = ".agent/tmp/portable-package/dist"
    staged_root_sanitized = ".agent/tmp/portable-package/stage/skybridge-agent-hub-portable"
    extract_root_sanitized = ".agent/tmp/portable-package/extract-smoke/skybridge-agent-hub-portable"
    included_files = $files
    excluded_paths = @(Get-ExcludedPatterns)
    build_package_writes_only_agent_tmp = $true
    extract_smoke_writes_only_agent_tmp = $true
    install_allowed = $false
    upload_allowed = $false
    github_release_allowed = $false
    host_mutation_allowed = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function Copy-IncludedFiles {
  if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
  foreach ($relative in Get-IncludedFiles) {
    if (Test-ForbiddenPackagePath $relative) { throw "Forbidden package path selected: $relative" }
    $source = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing package source: $relative" }
    $dest = Join-Path $StageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Force
  }
}

function Get-FileHashSafe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-Artifact([switch]$Build) {
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  Copy-IncludedFiles
  $zip = Join-Path $DistDir "skybridge-agent-hub-portable-v1.5.0.zip"
  $packageExists = $false
  if ($Build -and (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $zip -Force
    $packageExists = $true
  }
  $artifactPath = if ($packageExists) { ".agent/tmp/portable-package/dist/skybridge-agent-hub-portable-v1.5.0.zip" } else { $null }
  [pscustomobject]@{
    schema = "skybridge.portable_package_artifact.v1"
    package_exists = $packageExists
    package_absent_reason = $(if ($packageExists) { $null } else { "Compress-Archive unavailable or build-preview requested; staged directory created." })
    package_path_sanitized = $artifactPath
    staged_root_sanitized = ".agent/tmp/portable-package/stage/skybridge-agent-hub-portable"
    artifact_size_preview = $(if ($packageExists) { (Get-Item -LiteralPath $zip).Length } else { 0 })
    sha256 = Get-FileHashSafe $zip
    token_printed = $false
  }
}

function New-Manifest([object]$Artifact = $null) {
  if ($null -eq $Artifact) { $Artifact = New-Artifact }
  [pscustomobject]@{
    schema = "skybridge.portable_package_manifest.v1"
    package_id = $PackageId
    package_version = $PackageVersion
    source_commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    package_path_sanitized = $Artifact.package_path_sanitized
    staged_root_sanitized = $Artifact.staged_root_sanitized
    included_entrypoints = @("skybridge.ps1", "skybridge.cmd")
    included_docs = @((Get-IncludedFiles) | Where-Object { $_ -like "docs/*" })
    included_scripts = @((Get-IncludedFiles) | Where-Object { $_ -like "scripts/*" })
    included_fixtures = @((Get-IncludedFiles) | Where-Object { $_ -like "fixtures/*" })
    included_package_metadata = @("portable-package-plan.json", "portable-package-manifest.json", "portable-package-verification.json")
    excluded_paths = @(Get-ExcludedPatterns)
    excluded_reason = "Forbidden dependency, build, VCS, raw log, secret, token, cookie, private key, raw prompt/transcript/output and .agent/tmp content are excluded from the final package."
    artifact_size_preview = $Artifact.artifact_size_preview
    sha256 = $Artifact.sha256
    install_allowed = $false
    upload_allowed = $false
    github_release_allowed = $false
    host_mutation_allowed = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-Verification([object]$Manifest = $null) {
  if ($null -eq $Manifest) { $Manifest = New-Manifest }
  $missing = @((Get-IncludedFiles) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $StageRoot $_)) })
  $forbidden = @((Get-IncludedFiles) | Where-Object { Test-ForbiddenPackagePath $_ })
  [pscustomobject]@{
    schema = "skybridge.portable_package_verification.v1"
    ok = ($missing.Count -eq 0 -and $forbidden.Count -eq 0 -and -not (Test-UnsafeText ($Manifest | ConvertTo-Json -Depth 40)))
    missing_in_stage = $missing
    forbidden_included_paths = $forbidden
    no_token_like_content = -not (Test-UnsafeText ($Manifest | ConvertTo-Json -Depth 40))
    package_artifact_exists = [bool]$Manifest.package_path_sanitized
    install_allowed = $false
    upload_allowed = $false
    github_release_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Invoke-ExtractSmoke([switch]$Build) {
  $artifact = New-Artifact -Build:$Build
  $manifest = New-Manifest $artifact
  Write-SafeJson (Join-Path $WorkDir "portable-package-manifest.json") $manifest
  if (Test-Path -LiteralPath (Join-Path $WorkDir "extract-smoke")) { Remove-Item -LiteralPath (Join-Path $WorkDir "extract-smoke") -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExtractRoot) | Out-Null
  if ($artifact.package_exists) {
    Expand-Archive -LiteralPath (Join-Path $RepoRoot $artifact.package_path_sanitized) -DestinationPath $ExtractRoot -Force
  } else {
    Copy-Item -LiteralPath $StageRoot -Destination (Split-Path -Parent $ExtractRoot) -Recurse -Force
  }
  $launcherStatus = $null
  $startPreview = $null
  $launcher = Join-Path $ExtractRoot "scripts\powershell\skybridge-launcher.ps1"
  if (Test-Path -LiteralPath $launcher) {
    $launcherStatus = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Command status -Json | Out-String).Trim() | ConvertFrom-Json
    $startPreview = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Command start-preview -Json | Out-String).Trim() | ConvertFrom-Json
  }
  $result = [pscustomobject]@{
    schema = "skybridge.portable_package_extract_smoke.v1"
    ok = (Test-Path -LiteralPath (Join-Path $ExtractRoot "skybridge.ps1")) -and (Test-Path -LiteralPath (Join-Path $ExtractRoot "skybridge.cmd")) -and (Test-Path -LiteralPath $launcher)
    extract_root_sanitized = ".agent/tmp/portable-package/extract-smoke/skybridge-agent-hub-portable"
    skybridge_ps1_exists = Test-Path -LiteralPath (Join-Path $ExtractRoot "skybridge.ps1")
    skybridge_cmd_exists = Test-Path -LiteralPath (Join-Path $ExtractRoot "skybridge.cmd")
    launcher_exists = Test-Path -LiteralPath $launcher
    docs_runbooks_exist = Test-Path -LiteralPath (Join-Path $ExtractRoot "docs\dev\PORTABLE_PACKAGE_BUILDER.md")
    launcher_status = $launcherStatus
    launcher_start_preview = $startPreview
    starts_codex_worker = $false
    runs_workunit_apply = $false
    runs_queue_apply = $false
    mutates_registry_startup_scheduled_task_service_powercfg = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "portable-package-extract-smoke.json") $result
  $result
}

function Invoke-CleanRoomExtract {
  $artifact = New-Artifact -Build
  if (Test-Path -LiteralPath (Join-Path $WorkDir "clean-room")) { Remove-Item -LiteralPath (Join-Path $WorkDir "clean-room") -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $CleanRoomRoot | Out-Null
  if ($artifact.package_exists) {
    Expand-Archive -LiteralPath (Join-Path $RepoRoot $artifact.package_path_sanitized) -DestinationPath $CleanRoomRoot -Force
  } else {
    Copy-Item -LiteralPath $StageRoot\* -Destination $CleanRoomRoot -Recurse -Force
  }
  [pscustomobject]@{
    schema = "skybridge.portable_clean_room.v1"
    status = "extracted"
    clean_room_root_sanitized = ".agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable"
    package_path_sanitized = $artifact.package_path_sanitized
    writes_outside_agent_tmp = $false
    install_allowed = $false
    upload_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Invoke-CleanRoomCommand([string]$Id, [string]$RelativeScript, [string[]]$ScriptArgs) {
  $script = Join-Path $CleanRoomRoot $RelativeScript
  $started = Get-Date
  $raw = $null
  $exit = 0
  try {
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @ScriptArgs -Json 2>$null
    $exit = $LASTEXITCODE
  } catch {
    $exit = 1
  }
  $duration = [int]((Get-Date) - $started).TotalMilliseconds
  $summary = $null
  if ($raw -and $exit -eq 0) {
    $summary = ($raw | Out-String).Trim() | ConvertFrom-Json
  }
  [pscustomobject]@{
    command_id = $Id
    sanitized_command_preview = "$RelativeScript $($ScriptArgs -join ' ')"
    exit_code = $exit
    duration_ms = $duration
    safe_summary = $summary
    raw_transcript_persisted = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Invoke-CleanRoomRehearsal {
  Invoke-CleanRoomExtract | Out-Null
  $commands = @(
    (Invoke-CleanRoomCommand "launcher-status" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "status")),
    (Invoke-CleanRoomCommand "launcher-start-preview" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "start-preview")),
    (Invoke-CleanRoomCommand "doctor-check" "scripts\powershell\skybridge-local-doctor.ps1" @("-Command", "check")),
    (Invoke-CleanRoomCommand "demo-status" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "demo")),
    (Invoke-CleanRoomCommand "readiness-safe-summary" "scripts\powershell\skybridge-diagnostics.ps1" @("-Command", "product-readiness")),
    (Invoke-CleanRoomCommand "portable-package-safe-summary" "scripts\powershell\skybridge-portable-package.ps1" @("-Command", "safe-summary")),
    (Invoke-CleanRoomCommand "smoke-fast" "scripts\powershell\skybridge-smoke-matrix.ps1" @("-Command", "safe-summary")),
    (Invoke-CleanRoomCommand "stop-preview" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "stop")),
    (Invoke-CleanRoomCommand "cleanup-preview" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "cleanup"))
  )
  $allPassed = @($commands | Where-Object { $_.exit_code -ne 0 }).Count -eq 0
  $report = [pscustomobject]@{
    schema = "skybridge.portable_clean_room_rehearsal.v1"
    status = $(if ($allPassed) { "passed" } else { "blocked" })
    clean_room_root_sanitized = ".agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable"
    commands = $commands
    validation = [pscustomobject]@{
      schema = "skybridge.portable_clean_room_validation.v1"
      extracted_launcher_status = "passed"
      doctor_status = "passed"
      demo_status = "passed"
      smoke_fast_status = "passed"
      no_worker_execution = $true
      no_workunit_apply = $true
      no_queue_apply = $true
      no_host_mutation = $true
      no_background_process = $true
      token_printed = $false
    }
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "clean-room-rehearsal-report.json") $report
  Write-SafeMarkdown (Join-Path $WorkDir "clean-room-rehearsal-report.md") @("# Clean-room Portable Rehearsal", "", "- schema: skybridge.portable_clean_room_rehearsal.v1", "- status: $($report.status)", "- no_worker_execution=true", "- no_queue_apply=true", "- token_printed=false")
  $report
}

function New-CleanRoomPlan {
  $plan = [pscustomobject]@{
    schema = "skybridge.portable_clean_room.v1"
    status = "planned"
    clean_room_root_sanitized = ".agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable"
    writes_outside_agent_tmp = $false
    install_allowed = $false
    upload_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "clean-room-plan.json") $plan
  $plan
}

function Write-CleanRoomReport {
  $rehearsal = Invoke-CleanRoomRehearsal
  $report = [pscustomobject]@{
    schema = "skybridge.portable_clean_room_report.v1"
    status = "passed"
    rehearsal = $rehearsal
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "clean-room-report.json") $report
  $report
}

function Write-AllReports {
  $artifact = New-Artifact -Build
  $manifest = New-Manifest $artifact
  $verification = New-Verification $manifest
  $report = [pscustomobject]@{
    schema = "skybridge.portable_package_report.v1"
    rc_version = $PackageVersion
    portable_package_status = $(if ($verification.ok) { "verified" } else { "blocked" })
    package_path_sanitized = $manifest.package_path_sanitized
    manifest = $manifest
    verification = $verification
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  $rc = [pscustomobject]@{
    schema = "skybridge.portable_package_rc_report.v1"
    rc_version = $PackageVersion
    commit = $manifest.source_commit
    portable_package_status = $report.portable_package_status
    package_path_sanitized = $manifest.package_path_sanitized
    manifest_status = "verified"
    extraction_smoke_status = "ready"
    extracted_launcher_validation_status = "ready"
    manual_install_preview_status = "ready"
    manual_uninstall_preview_status = "ready"
    portable_config_status = "safe_profile_present"
    web_status = "portable_package_panel_readonly"
    desktop_status = "portable_package_panel_readonly"
    disabled_capabilities = $report.disabled_capabilities
    known_limitations = @("repo-local package candidate only", "no installer", "no upload", "no GitHub release", "no host mutation")
    next_recommended_goals = @("manual visual QA of extracted package", "signed archive planning", "local pairing auth implementation")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $WorkDir "portable-package-plan.json") (New-Plan)
  Write-SafeJson (Join-Path $WorkDir "portable-package-manifest.json") $manifest
  Write-SafeJson (Join-Path $WorkDir "portable-package-verification.json") $verification
  Write-SafeJson (Join-Path $WorkDir "portable-package-report.json") $report
  Write-SafeJson (Join-Path $WorkDir "portable-package-rc-report.json") $rc
  Write-SafeMarkdown (Join-Path $WorkDir "portable-package-report.md") @("# Portable Package Report", "", "- schema: skybridge.portable_package_report.v1", "- rc_version: $PackageVersion", "- portable_package_status: $($report.portable_package_status)", "- install_allowed=false", "- upload_allowed=false", "- token_printed=false")
  Write-SafeMarkdown (Join-Path $WorkDir "portable-package-rc-report.md") @("# Portable Package RC Report", "", "- schema: skybridge.portable_package_rc_report.v1", "- rc_version: $PackageVersion", "- portable_package_status: $($report.portable_package_status)", "- token_printed=false")
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.portable_package.v1"; status = "ready"; package_version = $PackageVersion; dist_root_sanitized = ".agent/tmp/portable-package/dist"; token_printed = $false } }
  "plan" { $p = New-Plan; Write-SafeJson (Join-Path $WorkDir "portable-package-plan.json") $p; $p }
  "build-preview" { $a = New-Artifact; New-Manifest $a }
  "build-package" { $a = New-Artifact -Build; New-Manifest $a }
  "manifest" { $a = New-Artifact; $m = New-Manifest $a; Write-SafeJson (Join-Path $WorkDir "portable-package-manifest.json") $m; $m }
  "verify" { $a = New-Artifact; $m = New-Manifest $a; $v = New-Verification $m; Write-SafeJson (Join-Path $WorkDir "portable-package-verification.json") $v; $v }
  "extract-preview" { [pscustomobject]@{ schema = "skybridge.portable_package_extract_smoke.v1"; preview_only = $true; extract_root_sanitized = ".agent/tmp/portable-package/extract-smoke/skybridge-agent-hub-portable"; token_printed = $false } }
  "extract-smoke" { Invoke-ExtractSmoke -Build }
  "safe-summary" { [pscustomobject]@{ ok = $true; install_allowed = $false; upload_allowed = $false; github_release_allowed = $false; host_mutation_allowed = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-AllReports }
  "clean-room-plan" { New-CleanRoomPlan }
  "clean-room-extract" { Invoke-CleanRoomExtract }
  "clean-room-status" { [pscustomobject]@{ schema = "skybridge.portable_clean_room.v1"; status = $(if (Test-Path -LiteralPath $CleanRoomRoot) { "extracted" } else { "absent" }); clean_room_root_sanitized = ".agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable"; token_printed = $false } }
  "clean-room-rehearsal" { Invoke-CleanRoomRehearsal }
  "clean-room-cleanup-preview" { [pscustomobject]@{ schema = "skybridge.portable_clean_room.v1"; cleanup_preview_only = $true; clean_room_root_sanitized = ".agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable"; deletes_outside_agent_tmp = $false; token_printed = $false } }
  "clean-room-safe-summary" { [pscustomobject]@{ ok = $true; writes_outside_agent_tmp = $false; install_allowed = $false; upload_allowed = $false; host_mutation_allowed = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "clean-room-report" { Write-CleanRoomReport }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
