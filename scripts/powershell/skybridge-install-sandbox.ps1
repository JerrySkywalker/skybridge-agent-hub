[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "apply-preview", "apply-sandbox", "verify", "list-files", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SandboxRoot = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
$CurrentRoot = Join-Path $SandboxRoot "current"
$PackagePath = Join-Path $RepoRoot ".agent\tmp\portable-package\dist\skybridge-agent-hub-portable-v1.5.0.zip"
$PortableManifestPath = Join-Path $RepoRoot ".agent\tmp\portable-package\portable-package-manifest.json"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Assert-UnderSandbox([string]$Path) {
  $root = [System.IO.Path]::GetFullPath($SandboxRoot)
  $target = [System.IO.Path]::GetFullPath($Path)
  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path escapes install sandbox: $Path"
  }
}

function Write-SafeJson([string]$Path, $Value) {
  Assert-UnderSandbox $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 50
  if (Test-UnsafeText $text) { throw "Refusing unsafe install sandbox JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  Assert-UnderSandbox $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe install sandbox markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-SandboxJson([string]$RelativeScript, [string[]]$Args) {
  $script = Join-Path $CurrentRoot $RelativeScript
  $started = Get-Date
  $exit = 0
  $summary = $null
  try {
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Args -Json 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 0 -and $raw) {
      $text = ($raw | Out-String).Trim()
      if (-not (Test-UnsafeText $text)) { $summary = $text | ConvertFrom-Json }
    }
  } catch {
    $exit = 1
  }
  [pscustomobject]@{
    command = "$RelativeScript $($Args -join ' ')"
    exit_code = $exit
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    safe_summary = $summary
    raw_output_persisted = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    mutates_host = $false
    token_printed = $false
  }
}

function Get-Plan {
  [pscustomobject]@{
    schema = "skybridge.install_sandbox_plan.v1"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    package_path_sanitized = ".agent/tmp/portable-package/dist/skybridge-agent-hub-portable-v1.5.0.zip"
    portable_manifest_sanitized = ".agent/tmp/portable-package/portable-package-manifest.json"
    writes_only_under_install_sandbox = $true
    install_allowed = $false
    host_install = $false
    registry_mutation = $false
    service_mutation = $false
    scheduled_task_mutation = $false
    startup_folder_mutation = $false
    path_mutation = $false
    powercfg_mutation = $false
    network_update = $false
    upload_allowed = $false
    token_printed = $false
  }
}

function Invoke-ApplyPreview {
  [pscustomobject]@{
    schema = "skybridge.install_sandbox.v1"
    mode = "apply-preview"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    package_exists = (Test-Path -LiteralPath $PackagePath)
    would_extract_archive = $true
    would_copy_safe_metadata = (Test-Path -LiteralPath $PortableManifestPath)
    writes_only_under_install_sandbox = $true
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Invoke-ApplySandbox {
  if (-not (Test-Path -LiteralPath $PackagePath)) { throw "Portable package artifact not found." }
  Assert-UnderSandbox $CurrentRoot
  if (Test-Path -LiteralPath $CurrentRoot) { Remove-Item -LiteralPath $CurrentRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $CurrentRoot | Out-Null
  Expand-Archive -LiteralPath $PackagePath -DestinationPath $CurrentRoot -Force
  $metadataDir = Join-Path $CurrentRoot ".skybridge"
  New-Item -ItemType Directory -Force -Path $metadataDir | Out-Null
  if (Test-Path -LiteralPath $PortableManifestPath) {
    Copy-Item -LiteralPath $PortableManifestPath -Destination (Join-Path $metadataDir "portable-package-manifest.json") -Force
  }
  $manifest = Get-Manifest
  Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-manifest.json") $manifest
  $manifest
}

function Test-ForbiddenSandboxPath([string]$RelativePath) {
  $p = $RelativePath.Replace("\", "/")
  return $p -match "(^|/)(\.git|node_modules|target|dist|build|\.next|coverage)(/|$)|(^|/)\.env|\.log$|(^|/)logs(/|$)|secret|token|key|cookie|(^|/)raw(/|$)"
}

function Get-RelativeFiles {
  if (-not (Test-Path -LiteralPath $CurrentRoot)) { return @() }
  @(Get-ChildItem -LiteralPath $CurrentRoot -Recurse -File | ForEach-Object {
    [System.IO.Path]::GetRelativePath($CurrentRoot, $_.FullName).Replace("\", "/")
  } | Sort-Object)
}

function Get-Manifest {
  $files = @(Get-RelativeFiles)
  [pscustomobject]@{
    schema = "skybridge.install_sandbox_manifest.v1"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    package_path_sanitized = ".agent/tmp/portable-package/dist/skybridge-agent-hub-portable-v1.5.0.zip"
    file_count = $files.Count
    files_preview = @($files | Select-Object -First 40)
    skybridge_ps1_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "skybridge.ps1")
    skybridge_cmd_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "skybridge.cmd")
    portable_manifest_copied = Test-Path -LiteralPath (Join-Path $CurrentRoot ".skybridge\portable-package-manifest.json")
    forbidden_paths = @($files | Where-Object { Test-ForbiddenSandboxPath $_ })
    token_printed = $false
  }
}

function Invoke-Verify {
  $files = @(Get-RelativeFiles)
  $required = @(
    "skybridge.ps1",
    "skybridge.cmd",
    "scripts/powershell/skybridge-launcher.ps1",
    "scripts/powershell/skybridge-local-session.ps1",
    "scripts/powershell/skybridge-local-doctor.ps1",
    "docs/dev/REPO_LOCAL_LAUNCHER.md"
  )
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $CurrentRoot $_)) })
  $forbidden = @($files | Where-Object { Test-ForbiddenSandboxPath $_ })
  $safeCommands = @()
  if ($missing.Count -eq 0) {
    $safeCommands = @(
      Invoke-SandboxJson "scripts\powershell\skybridge-launcher.ps1" @("-Command", "status")
      Invoke-SandboxJson "scripts\powershell\skybridge-launcher.ps1" @("-Command", "start-preview")
      Invoke-SandboxJson "scripts\powershell\skybridge-local-doctor.ps1" @("-Command", "check")
      Invoke-SandboxJson "scripts\powershell\skybridge-local-session.ps1" @("-Command", "demo")
      Invoke-SandboxJson "scripts\powershell\skybridge-portable-package.ps1" @("-Command", "safe-summary")
    )
  }
  $verification = [pscustomobject]@{
    schema = "skybridge.install_sandbox_verification.v1"
    ok = ($missing.Count -eq 0 -and $forbidden.Count -eq 0)
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    missing_required_paths = $missing
    forbidden_paths_absent = ($forbidden.Count -eq 0)
    forbidden_paths = $forbidden
    skybridge_ps1_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "skybridge.ps1")
    skybridge_cmd_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "skybridge.cmd")
    launcher_script_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "scripts\powershell\skybridge-launcher.ps1")
    local_session_script_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "scripts\powershell\skybridge-local-session.ps1")
    doctor_script_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot "scripts\powershell\skybridge-local-doctor.ps1")
    portable_manifest_exists = Test-Path -LiteralPath (Join-Path $CurrentRoot ".skybridge\portable-package-manifest.json")
    docs_runbooks_exist = Test-Path -LiteralPath (Join-Path $CurrentRoot "docs\dev\REPO_LOCAL_LAUNCHER.md")
    sandbox_safe_commands = $safeCommands
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-verification.json") $verification
  $verification
}

function Write-Report {
  $plan = Get-Plan
  $manifest = if (Test-Path -LiteralPath $CurrentRoot) { Get-Manifest } else { $null }
  $verification = if (Test-Path -LiteralPath $CurrentRoot) { Invoke-Verify } else { $null }
  $report = [pscustomobject]@{
    schema = "skybridge.install_sandbox_report.v1"
    status = if ($verification -and $verification.ok) { "passed" } elseif ($manifest) { "blocked" } else { "not_applied" }
    plan = $plan
    manifest = $manifest
    verification = $verification
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch", "host_install")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-plan.json") $plan
  if ($manifest) { Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-manifest.json") $manifest }
  Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-report.json") $report
  Write-SafeMarkdown (Join-Path $SandboxRoot "install-sandbox-report.md") @(
    "# Install Sandbox Report",
    "",
    "- schema: skybridge.install_sandbox_report.v1",
    "- status: $($report.status)",
    "- sandbox_root: .agent/tmp/install-sandbox/current",
    "- writes_only_under_install_sandbox=true",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.install_sandbox.v1"; status = $(if (Test-Path -LiteralPath $CurrentRoot) { "applied" } else { "empty" }); sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"; token_printed = $false } }
  "plan" { $p = Get-Plan; Write-SafeJson (Join-Path $SandboxRoot "install-sandbox-plan.json") $p; $p }
  "apply-preview" { Invoke-ApplyPreview }
  "apply-sandbox" { Invoke-ApplySandbox }
  "verify" { Invoke-Verify }
  "list-files" { [pscustomobject]@{ schema = "skybridge.install_sandbox_manifest.v1"; sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"; files = @(Get-RelativeFiles); token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; writes_only_under_install_sandbox = $true; host_install = $false; registry_mutation = $false; service_mutation = $false; scheduled_task_mutation = $false; startup_folder_mutation = $false; path_mutation = $false; powercfg_mutation = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 60 } else { $Result | Format-List | Out-String }
