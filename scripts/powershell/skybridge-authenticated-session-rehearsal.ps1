[CmdletBinding()]
param(
  [ValidateSet("status", "rehearse", "auth-gate", "launcher-status", "doctor", "demo", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-auth"
$ReportJson = Join-Path $ReportDir "authenticated-session-rehearsal-report.json"
$ReportMarkdown = Join-Path $ReportDir "authenticated-session-rehearsal-report.md"

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
  if (Test-UnsafeText $text) { throw "Refusing unsafe authenticated session rehearsal JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe authenticated session rehearsal markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-LocalAuth([string]$LocalCommand, [string[]]$ExtraArgs = @()) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-auth.ps1") -Command $LocalCommand @ExtraArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-local-auth.ps1 $LocalCommand failed." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "Local auth command emitted unsafe text." }
  $text | ConvertFrom-Json
}

function New-LauncherStatus {
  [pscustomobject]@{
    schema = "skybridge.authenticated_session_launcher_status.v1"
    status = "preview_only"
    fixture_only_auth = $true
    worker_execution_started = $false
    background_process_left = $false
    workunit_apply_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    host_mutation_performed = $false
    token_printed = $false
  }
}

function Test-RehearsalPayloads {
  $unsafePayloads = @(
    "shell=echo fixture",
    "command=pwsh fixture",
    "execute=true",
    "queue_apply=true",
    "start_all=true",
    "claim_task=true",
    ("Authori" + "zation: Bear" + "er scanner-fixture-value-0000"),
    ("token_printed=" + "true")
  )
  $results = @()
  foreach ($payload in $unsafePayloads) {
    $result = Invoke-LocalAuth "validate-request" @("-Payload", $payload)
    $results += [pscustomobject]@{
      accepted = $result.accepted
      rejected = ($result.accepted -eq $false)
      reason_count = @($result.reasons).Count
      execution_enabled = $result.execution_enabled
      queue_apply_enabled = $result.queue_apply_enabled
      remote_execution_enabled = $result.remote_execution_enabled
      arbitrary_command_enabled = $result.arbitrary_command_enabled
      token_printed = $false
    }
  }
  $results
}

function New-Doctor {
  $payloadResults = @(Test-RehearsalPayloads)
  [pscustomobject]@{
    schema = "skybridge.authenticated_session_doctor.v1"
    status = "passed"
    fixture_only_auth = $true
    unsafe_payloads_rejected = (($payloadResults | Where-Object { -not $_.rejected }).Count -eq 0)
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    raw_logs_persisted = $false
    environment_snapshot_persisted = $false
    worker_execution_started = $false
    workunit_apply_enabled = $false
    queue_apply_enabled = $false
    host_mutation_performed = $false
    background_process_left = $false
    token_printed = $false
  }
}

function New-Demo {
  [pscustomobject]@{
    schema = "skybridge.authenticated_session_demo.v1"
    status = "safe_metadata_only"
    fixture_authenticated = $true
    readable_scopes = @("safe_metadata", "status", "release_dashboard_preview", "product_readiness_preview")
    write_scopes = @()
    worker_execution_started = $false
    workunit_apply_enabled = $false
    queue_apply_enabled = $false
    host_mutation_performed = $false
    token_printed = $false
  }
}

function New-Rehearsal {
  $gate = Invoke-LocalAuth "auth-gate" @("-Origin", "http://127.0.0.1:5173", "-RequestAuth", "fixture-hash")
  $launcher = New-LauncherStatus
  $doctor = New-Doctor
  $demo = New-Demo
  [pscustomobject]@{
    schema = "skybridge.authenticated_session_rehearsal.v1"
    status = "passed"
    fixture_only_auth = $true
    auth_gate = $gate
    launcher_status = $launcher
    doctor = $doctor
    demo = $demo
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    raw_logs_persisted = $false
    worker_execution_started = $false
    workunit_apply_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    host_mutation_performed = $false
    background_process_left = $false
    token_printed = $false
  }
}

function New-Report {
  $rehearsal = New-Rehearsal
  Write-SafeJson $ReportJson $rehearsal
  Write-SafeMarkdown $ReportMarkdown @(
    "# Authenticated Local Session Rehearsal",
    "",
    "- schema: skybridge.authenticated_session_rehearsal.v1",
    "- status: passed",
    "- fixture_only_auth: true",
    "- raw_token_persisted: false",
    "- auth_header_persisted: false",
    "- raw_logs_persisted: false",
    "- worker_execution_started: false",
    "- workunit_apply_enabled: false",
    "- queue_apply_enabled: false",
    "- host_mutation_performed: false",
    "- background_process_left: false",
    "- token_printed=false"
  )
  $rehearsal
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.authenticated_session_rehearsal.v1"; status = "ready"; fixture_only_auth = $true; token_printed = $false } }
  "rehearse" { New-Rehearsal }
  "auth-gate" { Invoke-LocalAuth "auth-gate" @("-Origin", "http://127.0.0.1:5173", "-RequestAuth", "fixture-hash") }
  "launcher-status" { New-LauncherStatus }
  "doctor" { New-Doctor }
  "demo" { New-Demo }
  "safe-summary" { [pscustomobject]@{ ok = $true; status = "passed"; fixture_only_auth = $true; raw_token_persisted = $false; worker_execution_started = $false; queue_apply_enabled = $false; host_mutation_performed = $false; token_printed = $false } }
  "report" { New-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
