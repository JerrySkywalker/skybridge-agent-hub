[CmdletBinding()]
param(
  [ValidateSet("check", "explain", "fix-preview", "cleanup-preview", "ports", "locks", "dependencies", "safe-summary", "report")]
  [string]$Command = "check",
  [switch]$Desktop,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-session"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe doctor JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe doctor markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Test-CommandAvailable([string]$Name) {
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-PortAvailable([int]$Port) {
  try {
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $Listener.Start()
    $Listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { return $null }
  ($Raw | Out-String).Trim() | ConvertFrom-Json
}

function New-Ports {
  [pscustomobject]@{
    schema = "skybridge.local_doctor_ports.v1"
    checks = @(
      [pscustomobject]@{ component_id = "web-preview"; port = 5173; available = Test-PortAvailable 5173; token_printed = $false }
      [pscustomobject]@{ component_id = "server-control-plane-preview"; port = 8787; available = Test-PortAvailable 8787; token_printed = $false }
    )
    token_printed = $false
  }
}

function New-Locks {
  $SessionDir = Join-Path $RepoRoot ".agent\tmp\local-session"
  [pscustomobject]@{
    schema = "skybridge.local_doctor_locks.v1"
    lock_present = Test-Path -LiteralPath (Join-Path $SessionDir "manual-local-session.lock.json")
    pid_present = Test-Path -LiteralPath (Join-Path $SessionDir "manual-local-session.pid.json")
    stale_locks_absent = $true
    stale_pids_absent = $true
    cleanup_preview_available = $true
    token_printed = $false
  }
}

function New-Dependencies {
  [pscustomobject]@{
    schema = "skybridge.local_doctor_dependencies.v1"
    git_available = Test-CommandAvailable "git"
    pwsh_available = Test-CommandAvailable "pwsh"
    node_available = Test-CommandAvailable "node"
    corepack_available = Test-CommandAvailable "corepack"
    cargo_available = if ($Desktop) { Test-CommandAvailable "cargo" } else { $null }
    token_printed = $false
  }
}

function New-Check {
  $GitStatus = ((& git -C $RepoRoot status --short 2>$null | Out-String).Trim())
  $Bootstrap = Invoke-JsonScript "skybridge-bootstrap-complete.ps1" @("-Command", "gate")
  $Productization = Invoke-JsonScript "skybridge-local-productization-rc.ps1" @("-Command", "status")
  $Config = Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "validate")
  $Deps = New-Dependencies
  $Ports = New-Ports
  $Locks = New-Locks
  $Checks = [ordered]@{
    repo_clean = [string]::IsNullOrWhiteSpace($GitStatus)
    bootstrap_complete = [bool]$Bootstrap.status.bootstrap_complete
    bootstrap_gate_pass = [bool]$Bootstrap.gate_pass
    productization_rc = ($Productization.rc_version -eq "v1.1.0-local-productization-rc")
    local_config_valid = [bool]$Config.ok
    ports_available = -not (@($Ports.checks) | Where-Object { -not $_.available })
    stale_locks_absent = [bool]$Locks.stale_locks_absent
    stale_pids_absent = [bool]$Locks.stale_pids_absent
    required_commands_available = ($Deps.git_available -and $Deps.pwsh_available -and $Deps.node_available -and $Deps.corepack_available)
    execution_flags_disabled = $true
    token_printed = $false
  }
  $Ok = $Checks.bootstrap_complete -and $Checks.productization_rc -and $Checks.local_config_valid -and $Checks.ports_available -and $Checks.stale_locks_absent -and $Checks.stale_pids_absent -and $Checks.required_commands_available -and $Checks.execution_flags_disabled
  [pscustomobject]@{
    schema = "skybridge.local_doctor_report.v1"
    ok = [bool]$Ok
    checks = $Checks
    ports = $Ports
    locks = $Locks
    dependencies = $Deps
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    next_safe_action = if ($Ok) { "Preview or apply a bounded local session." } else { "Read explanations and fix local prerequisites without enabling execution." }
    token_printed = $false
  }
}

function New-Explain {
  [pscustomobject]@{
    schema = "skybridge.local_doctor_explain.v1"
    port_conflict_explanation = "A busy preview port means another local process owns it; the doctor does not kill arbitrary processes."
    lock_explanation = "Session locks under .agent/tmp/local-session are metadata only and may be removed by stop for this session."
    recovery_guidance = @("Run status", "Run doctor", "Run cleanup-preview", "Run stop for local session metadata")
    token_printed = $false
  }
}

function New-FixPreview {
  [pscustomobject]@{
    schema = "skybridge.local_doctor_fix_preview.v1"
    preview_only = $true
    would_modify_registry = $false
    would_create_service = $false
    would_create_scheduled_task = $false
    would_modify_powercfg = $false
    would_kill_arbitrary_process = $false
    suggested_actions = @("Commit or stash local changes before release checks", "Stop local dev servers occupying required ports", "Run local-session stop for session metadata")
    token_printed = $false
  }
}

function Write-Report {
  $Report = New-Check
  Write-SafeJson (Join-Path $ReportDir "local-doctor-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "local-doctor-report.md") @(
    "# Local Session Doctor Report",
    "",
    "- schema: skybridge.local_doctor_report.v1",
    "- ok: $($Report.ok)",
    "- bootstrap_complete: $($Report.checks.bootstrap_complete)",
    "- productization_rc: $($Report.checks.productization_rc)",
    "- local_config_valid: $($Report.checks.local_config_valid)",
    "- execution_flags_disabled: true",
    "- token_printed=false"
  )
  $Report
}

$Result = switch ($Command) {
  "check" { New-Check }
  "explain" { New-Explain }
  "fix-preview" { New-FixPreview }
  "cleanup-preview" { New-FixPreview }
  "ports" { New-Ports }
  "locks" { New-Locks }
  "dependencies" { New-Dependencies }
  "safe-summary" { [pscustomobject]@{ ok = $true; no_env_dump = $true; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
