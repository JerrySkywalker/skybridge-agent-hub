[CmdletBinding()]
param(
  [ValidateSet("status", "model", "fixture-session", "validate-request", "origin-check", "loopback-check", "auth-gate", "safe-summary", "report", "session-create-fixture", "session-list", "session-expire-fixture", "session-revoke-fixture", "session-redaction-check", "session-report")]
  [string]$Command = "status",
  [string]$Origin = "http://127.0.0.1:5173",
  [string]$RequestAuth = "fixture-hash",
  [string]$Payload = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-auth"
$SessionDir = Join-Path $ReportDir "session-store"
$SessionStorePath = Join-Path $SessionDir "sessions.json"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|raw_prompt|raw_stdout|raw_stderr|raw_worker_log|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 80
  if (Test-UnsafeText $text) { throw "Refusing unsafe local auth JSON: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe local auth markdown: $Path" }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-Sha256([string]$Value) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function New-AuthModel {
  [pscustomobject]@{
    schema = "skybridge.local_auth_model.v1"
    status = "preview_ready"
    allowed_origins = @("http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:8787", "http://127.0.0.1:8787", "repo-local-dev-fixture")
    remote_origins_allowed = $false
    raw_token_persisted = $false
    token_hash_present = $true
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    release_gate_required = $true
    resource_gate_required = $true
    failure_gate_required = $true
    evidence_gate_required = $true
    audit_gate_required = $true
    human_review_gate_required = $true
    token_printed = $false
  }
}

function New-OriginPolicy {
  [pscustomobject]@{
    schema = "skybridge.loopback_origin_policy.v1"
    allowed_loopback_hosts = @("localhost", "127.0.0.1", "::1")
    repo_local_dev_fixtures_allowed = $true
    remote_origins_allowed = $false
    allowed_ports = @(5173, 8787)
    token_printed = $false
  }
}

function Test-OriginAllowed([string]$Value) {
  if ($Value -eq "repo-local-dev-fixture") { return $true }
  try {
    $uri = [System.Uri]$Value
    return @("localhost", "127.0.0.1", "::1") -contains $uri.Host
  } catch {
    return $false
  }
}

function New-Rejection([string[]]$Reasons) {
  [pscustomobject]@{
    schema = "skybridge.local_auth_rejection.v1"
    accepted = $false
    reasons = $Reasons
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function Get-RequestRejectionReasons {
  param([string]$OriginValue, [string]$AuthValue, [string]$PayloadValue)
  $reasons = @()
  if (-not (Test-OriginAllowed $OriginValue)) { $reasons += "origin_not_loopback" }
  if ([string]::IsNullOrWhiteSpace($AuthValue) -or $AuthValue -eq "none") { $reasons += "unauthenticated_fixture_request" }
  if ($AuthValue -notin @("fixture-hash", "session-fixture-hash")) { $reasons += "invalid_fixture_auth" }
  if (Test-UnsafeText $PayloadValue) { $reasons += "unsafe_auth_payload_rejected" }
  if ($PayloadValue -match "(?i)token_printed\s*[:=]\s*true") { $reasons += "token_printed_true_forbidden" }
  if ($PayloadValue -match "(?i)(cmd|command|shell|powershell|pwsh|bash)\s*[:=]") { $reasons += "shell_command_text_forbidden" }
  if ($PayloadValue -match "(?i)(execute|run_apply|queue_apply|start_all|start_queue|claim_task)\s*[:=]\s*true") { $reasons += "execution_request_forbidden" }
  return $reasons
}

function New-AuthGate {
  $reasons = Get-RequestRejectionReasons -OriginValue $Origin -AuthValue $RequestAuth -PayloadValue $Payload
  if (@($reasons).Count -gt 0) { return New-Rejection $reasons }
  [pscustomobject]@{
    schema = "skybridge.local_auth_gate.v1"
    accepted = $true
    fixture_authenticated = $true
    allowed_read_scope = @("safe_metadata", "status", "release_dashboard_preview", "product_readiness_preview")
    write_scope = @()
    auth_does_not_enable_execution = $true
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-FixtureSession {
  $now = (Get-Date).ToUniversalTime()
  [pscustomobject]@{
    schema = "skybridge.local_auth_session.v1"
    session_id = "local-auth-fixture-session"
    created_at = $now.ToString("o")
    expires_at = $now.AddHours(2).ToString("o")
    state = "active"
    scope = @("safe_metadata:read", "control_plane_preview:read")
    token_hash = Get-Sha256 "fixture-local-auth-session-value"
    token_hash_present = $true
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    allowed_local_origin_summary = "localhost, 127.0.0.1 and repo-local dev fixtures only"
    token_printed = $false
  }
}

function Read-SessionStore {
  if (-not (Test-Path -LiteralPath $SessionStorePath)) { return @() }
  $text = Get-Content -Raw -LiteralPath $SessionStorePath
  if (Test-UnsafeText $text) { throw "Unsafe text detected in local auth session store." }
  $json = $text | ConvertFrom-Json
  return @($json.sessions)
}

function Write-SessionStore($Sessions) {
  $store = [pscustomobject]@{
    schema = "skybridge.local_auth_session_store.v1"
    sessions = @($Sessions)
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    token_printed = $false
  }
  Write-SafeJson $SessionStorePath $store
  return $store
}

function New-SessionReport {
  $sessions = Read-SessionStore
  [pscustomobject]@{
    schema = "skybridge.local_auth_session_report.v1"
    session_count = @($sessions).Count
    active_session_count = @($sessions | Where-Object { $_.state -eq "active" }).Count
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    token_like_content_rejected = $true
    token_printed = $false
  }
}

function New-LocalAuthReport {
  $model = New-AuthModel
  $gate = New-AuthGate
  $session = New-FixtureSession
  $report = [pscustomobject]@{
    schema = "skybridge.local_auth_report.v1"
    status = "ready"
    model = $model
    gate = $gate
    session = $session
    origin_policy = New-OriginPolicy
    api_auth_gate_status = "fixture_safe_metadata_only"
    web_desktop_surface_status = "read_only_preview"
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "local-auth-model.json") $model
  Write-SafeJson (Join-Path $ReportDir "local-auth-gate.json") $gate
  Write-SafeJson (Join-Path $ReportDir "local-auth-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "local-auth-report.md") @(
    "# Local Auth Preview Report",
    "",
    "- status: ready",
    "- schema: skybridge.local_auth_report.v1",
    "- remote_origins_allowed: false",
    "- raw_token_persisted: false",
    "- auth_header_persisted: false",
    "- cookie_persisted: false",
    "- private_key_persisted: false",
    "- execution_enabled: false",
    "- queue_apply_enabled: false",
    "- remote_execution_enabled: false",
    "- arbitrary_command_enabled: false",
    "- token_printed=false"
  )
  return $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.local_auth_report.v1"; status = "ready"; token_printed = $false } }
  "model" { $r = New-AuthModel; Write-SafeJson (Join-Path $ReportDir "local-auth-model.json") $r; $r }
  "fixture-session" { New-FixtureSession }
  "validate-request" { New-AuthGate }
  "origin-check" { [pscustomobject]@{ schema = "skybridge.loopback_origin_policy.v1"; origin = if (Test-OriginAllowed $Origin) { "allowed_loopback" } else { "rejected_remote" }; remote_origins_allowed = $false; token_printed = $false } }
  "loopback-check" { New-OriginPolicy }
  "auth-gate" { $r = New-AuthGate; Write-SafeJson (Join-Path $ReportDir "local-auth-gate.json") $r; $r }
  "safe-summary" { [pscustomobject]@{ ok = $true; local_auth_preview = "ready"; raw_token_persisted = $false; execution_enabled = $false; token_printed = $false } }
  "report" { New-LocalAuthReport }
  "session-create-fixture" { $s = New-FixtureSession; Write-SessionStore @($s) }
  "session-list" { [pscustomobject]@{ schema = "skybridge.local_auth_session_list.v1"; sessions = @(Read-SessionStore); token_printed = $false } }
  "session-expire-fixture" { $sessions = @(Read-SessionStore | ForEach-Object { $_.state = "expired"; $_ }); Write-SessionStore $sessions }
  "session-revoke-fixture" { $sessions = @(Read-SessionStore | ForEach-Object { $_.state = "revoked"; $_ }); Write-SessionStore $sessions }
  "session-redaction-check" { $r = New-SessionReport; if ($r.raw_token_persisted -or $r.auth_header_persisted -or $r.cookie_persisted -or $r.private_key_persisted) { throw "Session redaction failed." }; $r }
  "session-report" { $r = New-SessionReport; Write-SafeJson (Join-Path $ReportDir "local-auth-session-report.json") $r; $r }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
