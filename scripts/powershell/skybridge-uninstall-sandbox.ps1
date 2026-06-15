[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "uninstall-preview", "uninstall-sandbox", "verify-clean", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SandboxRoot = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
$CurrentRoot = Join-Path $SandboxRoot "current"

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
  $text = $Value | ConvertTo-Json -Depth 40
  if (Test-UnsafeText $text) { throw "Refusing unsafe uninstall sandbox JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  Assert-UnderSandbox $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe uninstall sandbox markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-CurrentFileCount {
  if (-not (Test-Path -LiteralPath $CurrentRoot)) { return 0 }
  @(Get-ChildItem -LiteralPath $CurrentRoot -Recurse -File).Count
}

function Get-Plan {
  [pscustomobject]@{
    schema = "skybridge.uninstall_sandbox_plan.v1"
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    current_exists = Test-Path -LiteralPath $CurrentRoot
    file_count = Get-CurrentFileCount
    deletes_only_under_current_sandbox = $true
    preserves_reports_outside_current = $true
    registry_mutation = $false
    startup_folder_mutation = $false
    service_mutation = $false
    scheduled_task_mutation = $false
    path_mutation = $false
    powercfg_mutation = $false
    token_printed = $false
  }
}

function Invoke-UninstallSandbox {
  Assert-UnderSandbox $CurrentRoot
  if (Test-Path -LiteralPath $CurrentRoot) {
    Remove-Item -LiteralPath $CurrentRoot -Recurse -Force
  }
  Invoke-VerifyClean
}

function Invoke-VerifyClean {
  [pscustomobject]@{
    schema = "skybridge.uninstall_sandbox_report.v1"
    status = if (Test-Path -LiteralPath $CurrentRoot) { "blocked" } else { "clean" }
    sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"
    current_exists = Test-Path -LiteralPath $CurrentRoot
    reports_preserved = Test-Path -LiteralPath $SandboxRoot
    deletes_outside_install_sandbox = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $plan = Get-Plan
  $clean = Invoke-VerifyClean
  $report = [pscustomobject]@{
    schema = "skybridge.uninstall_sandbox_report.v1"
    status = $clean.status
    plan = $plan
    clean_verification = $clean
    disabled_capabilities = @("host_uninstall", "registry_mutation", "startup_folder_mutation", "service_mutation", "scheduled_task_mutation", "path_mutation", "powercfg_mutation")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "uninstall-sandbox-plan.json") $plan
  Write-SafeJson (Join-Path $SandboxRoot "uninstall-sandbox-report.json") $report
  Write-SafeMarkdown (Join-Path $SandboxRoot "uninstall-sandbox-report.md") @(
    "# Uninstall Sandbox Report",
    "",
    "- schema: skybridge.uninstall_sandbox_report.v1",
    "- status: $($report.status)",
    "- deletes_only_under_current_sandbox=true",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.uninstall_sandbox.v1"; status = $(if (Test-Path -LiteralPath $CurrentRoot) { "installed_in_sandbox" } else { "clean" }); sandbox_root_sanitized = ".agent/tmp/install-sandbox/current"; token_printed = $false } }
  "plan" { $p = Get-Plan; Write-SafeJson (Join-Path $SandboxRoot "uninstall-sandbox-plan.json") $p; $p }
  "uninstall-preview" { Get-Plan }
  "uninstall-sandbox" { Invoke-UninstallSandbox }
  "verify-clean" { Invoke-VerifyClean }
  "safe-summary" { [pscustomobject]@{ ok = $true; deletes_only_under_current_sandbox = $true; preserves_reports_outside_current = $true; registry_mutation = $false; startup_folder_mutation = $false; service_mutation = $false; scheduled_task_mutation = $false; path_mutation = $false; powercfg_mutation = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
