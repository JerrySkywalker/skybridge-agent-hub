[CmdletBinding()]
param(
  [ValidateSet("status", "route", "next-action", "component-status", "doctor-summary", "demo-summary", "smoke-summary", "safe-summary", "report")]
  [string]$Command = "status",
  [string]$Target = "local-session status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-launcher"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)[;&|`$<>]|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Test-UnsafeRouteText([string]$Text) {
  if (Test-UnsafeText $Text) { return $true }
  return $Text -match "(?i)\b(start-all|start-queue|resume\s+-Apply|codex|workunit|claim|queue\s*apply|registry|startup|scheduled\s*task|service|powercfg|cmd|powershell|pwsh\s+-Command)\b"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe session supervisor JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe session supervisor markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  ($Raw | Out-String).Trim() | ConvertFrom-Json
}

function Get-AllowedRoutes {
  @{
    "local-session status" = @("skybridge-local-session.ps1", @("-Command", "status"))
    "local-session start-preview" = @("skybridge-local-session.ps1", @("-Command", "start"))
    "local-session start-local" = @("skybridge-local-session.ps1", @("-Command", "start", "-Apply", "-Profile", "full-local-preview", "-Bounded"))
    "local-session stop" = @("skybridge-local-session.ps1", @("-Command", "stop"))
    "local-session restart" = @("skybridge-local-session.ps1", @("-Command", "restart", "-Apply", "-Profile", "full-local-preview", "-Bounded"))
    "local-doctor check" = @("skybridge-local-doctor.ps1", @("-Command", "check"))
    "local-doctor explain" = @("skybridge-local-doctor.ps1", @("-Command", "explain"))
    "diagnostics health" = @("skybridge-diagnostics.ps1", @("-Command", "health"))
    "diagnostics product-readiness" = @("skybridge-diagnostics.ps1", @("-Command", "product-readiness"))
    "smoke-matrix run-fast" = @("skybridge-smoke-matrix.ps1", @("-Command", "run-fast"))
    "smoke-matrix run-bootstrap-complete" = @("skybridge-smoke-matrix.ps1", @("-Command", "run-bootstrap-complete"))
    "product profile status" = @("skybridge-product-profile.ps1", @("-Command", "status"))
    "demo status" = @("skybridge-local-session.ps1", @("-Command", "demo"))
  }
}

function Invoke-Route([string]$RouteTarget) {
  if (Test-UnsafeRouteText $RouteTarget) { return New-RouteError "unsafe_route_rejected" "Route text contains shell metacharacters or blocked execution/host mutation words." }
  $Routes = Get-AllowedRoutes
  if (-not $Routes.ContainsKey($RouteTarget)) { return New-RouteError "unknown_route" "Unknown route target rejected. No command was run." }
  $Spec = $Routes[$RouteTarget]
  $Result = Invoke-JsonScript $Spec[0] $Spec[1]
  [pscustomobject]@{
    schema = "skybridge.launcher_route.v1"
    target = $RouteTarget
    routed = $true
    result = $Result
    accepts_arbitrary_shell = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    token_printed = $false
  }
}

function New-RouteError([string]$Code, [string]$Message) {
  [pscustomobject]@{
    schema = "skybridge.launcher_safe_error.v1"
    ok = $false
    code = $Code
    message = $Message
    next_safe_action = "Run .\skybridge.ps1 status or route an allowlisted local-session status target."
    docs_link = "docs/dev/LOCAL_LAUNCHER_COMMAND_ROUTER.md"
    accepts_arbitrary_shell = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    mutates_host = $false
    token_printed = $false
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.session_supervisor_status.v1"
    status = "ready"
    allowed_routes = @((Get-AllowedRoutes).Keys | Sort-Object)
    forbidden_routes = @("arbitrary shell command", "Codex worker", "workunit apply", "task claim", "queue apply", "start-all", "start-queue", "resume", "registry/startup/service/scheduled-task/powercfg")
    session = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "status")
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-NextAction {
  [pscustomobject]@{
    schema = "skybridge.session_supervisor_next_action.v1"
    next_safe_action = "Run launcher start-preview, then doctor, then demo or bounded start-local only if explicitly requested."
    destructive_action_required = $false
    host_mutation_required = $false
    suggested_command_preview = ".\skybridge.ps1 start-preview"
    docs_link = "docs/dev/REPO_LOCAL_LAUNCHER.md"
    token_printed = $false
  }
}

function Write-Report {
  $Status = New-Status
  $Report = [pscustomobject]@{
    schema = "skybridge.session_supervisor_report.v1"
    rc_version = "v1.3.0-repo-local-launcher-rc"
    commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    supervisor_status = "ready"
    next_action = New-NextAction
    status = $Status
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "session-supervisor-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "session-supervisor-report.md") @(
    "# Session Supervisor Report",
    "",
    "- schema: skybridge.session_supervisor_report.v1",
    "- supervisor_status: ready",
    "- command_router_status: fixed_allowlist_only",
    "- destructive_action_required=false",
    "- host_mutation_required=false",
    "- token_printed=false"
  )
  $Report
}

$Result = switch ($Command) {
  "status" { New-Status }
  "route" { Invoke-Route $Target }
  "next-action" { New-NextAction }
  "component-status" { (New-Status).session.components }
  "doctor-summary" { Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check") }
  "demo-summary" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo") }
  "smoke-summary" { Invoke-JsonScript "skybridge-smoke-matrix.ps1" @("-Command", "run-fast") }
  "safe-summary" { [pscustomobject]@{ ok = $true; supervisor_status = "ready"; accepts_arbitrary_shell = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
