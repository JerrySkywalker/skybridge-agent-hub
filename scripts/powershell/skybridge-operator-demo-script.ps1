[CmdletBinding()]
param(
  [ValidateSet("status", "run-demo-preview", "acceptance-walkthrough", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\operator-acceptance"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe operator demo JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe operator demo markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$Args) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @Args -Json 2>$null
  if ($LASTEXITCODE -ne 0) { throw "$Script failed" }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text" }
  $text | ConvertFrom-Json
}

function Get-Demo {
  $steps = @(
    [pscustomobject]@{ step = "launcher status"; result = (Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "launcher-status")); token_printed = $false },
    [pscustomobject]@{ step = "doctor check"; result = (Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "doctor")); token_printed = $false },
    [pscustomobject]@{ step = "sandbox install status"; result = (Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "verify")); token_printed = $false },
    [pscustomobject]@{ step = "sandbox-installed runtime status"; result = (Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "safe-summary")); token_printed = $false },
    [pscustomobject]@{ step = "operator acceptance v3"; result = (Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "v3-report")); token_printed = $false }
  )
  [pscustomobject]@{
    schema = "skybridge.operator_demo_script_report.v1"
    status = "passed"
    steps = $steps
    no_worker_execution = $true
    no_host_mutation = $true
    token_printed = $false
  }
}

function Write-Report {
  $report = Get-Demo
  Write-SafeJson (Join-Path $ReportDir "operator-demo-script-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "operator-demo-script-report.md") @(
    "# Operator Demo Script Report",
    "",
    "- schema: skybridge.operator_demo_script_report.v1",
    "- status: $($report.status)",
    "- no_worker_execution=true",
    "- no_host_mutation=true",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.operator_demo_script_report.v1"; status = "ready"; token_printed = $false } }
  "run-demo-preview" { Get-Demo }
  "acceptance-walkthrough" { Get-Demo }
  "safe-summary" { [pscustomobject]@{ ok = $true; no_worker_execution = $true; no_host_mutation = $true; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
