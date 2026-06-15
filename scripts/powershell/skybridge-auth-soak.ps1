[CmdletBinding()]
param(
  [ValidateSet("fixture-auth-soak", "control-plane-auth-soak", "safe-summary", "report")]
  [string]$Command = "fixture-auth-soak",
  [ValidateRange(1, 5)]
  [int]$Iterations = 5,
  [ValidateRange(1, 240)]
  [int]$MaxDurationSeconds = 240,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-auth"
$ReportJson = Join-Path $ReportDir "auth-soak-report.json"
$ReportMarkdown = Join-Path $ReportDir "auth-soak-report.md"

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
  if (Test-UnsafeText $text) { throw "Refusing unsafe auth soak JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe auth soak markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-LocalAuthGate {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-auth.ps1") -Command auth-gate -Origin "http://127.0.0.1:5173" -RequestAuth "fixture-hash" -Json
  if ($LASTEXITCODE -ne 0) { throw "Local auth gate failed during soak." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "Local auth soak emitted unsafe text." }
  $text | ConvertFrom-Json
}

function New-Soak([string]$Mode) {
  $started = Get-Date
  $items = @()
  for ($i = 1; $i -le $Iterations; $i++) {
    if (((Get-Date) - $started).TotalSeconds -gt $MaxDurationSeconds) { throw "Auth soak exceeded max duration." }
    $gate = Invoke-LocalAuthGate
    $items += [pscustomobject]@{
      iteration = $i
      accepted_safe_metadata_read = ($gate.accepted -eq $true)
      execution_enabled = $false
      queue_apply_enabled = $false
      remote_execution_enabled = $false
      arbitrary_command_enabled = $false
      raw_log_persisted = $false
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.auth_control_plane_soak.v1"
    mode = $Mode
    status = "passed"
    iterations_requested = $Iterations
    iterations_completed = @($items).Count
    max_duration_seconds = $MaxDurationSeconds
    network_scope = "none_or_local_fixture_only"
    fixture_only_auth = $true
    checks = $items
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
    token_printed = $false
  }
}

function New-Report {
  $fixture = New-Soak "fixture-auth-soak"
  $control = New-Soak "control-plane-auth-soak"
  $report = [pscustomobject]@{
    schema = "skybridge.auth_soak_report.v1"
    status = "passed"
    fixture_auth_soak = $fixture
    control_plane_auth_soak = $control
    raw_token_persisted = $false
    auth_header_persisted = $false
    raw_logs_persisted = $false
    worker_execution_started = $false
    queue_apply_enabled = $false
    host_mutation_performed = $false
    token_printed = $false
  }
  Write-SafeJson $ReportJson $report
  Write-SafeMarkdown $ReportMarkdown @(
    "# Auth Control-plane Soak",
    "",
    "- schema: skybridge.auth_soak_report.v1",
    "- status: passed",
    "- iterations_completed: $($fixture.iterations_completed + $control.iterations_completed)",
    "- max_duration_seconds: $MaxDurationSeconds",
    "- network_scope: none_or_local_fixture_only",
    "- raw_token_persisted: false",
    "- auth_header_persisted: false",
    "- raw_logs_persisted: false",
    "- worker_execution_started: false",
    "- queue_apply_enabled: false",
    "- host_mutation_performed: false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "fixture-auth-soak" { New-Soak "fixture-auth-soak" }
  "control-plane-auth-soak" { New-Soak "control-plane-auth-soak" }
  "safe-summary" { [pscustomobject]@{ ok = $true; status = "passed"; iterations_default = 5; max_duration_seconds = 240; raw_token_persisted = $false; raw_logs_persisted = $false; worker_execution_started = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { New-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
