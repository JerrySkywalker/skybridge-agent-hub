[CmdletBinding()]
param(
  [ValidateSet("profile-list", "profile-show", "profile-validate", "safe-summary", "report")]
  [string]$Command = "profile-list",
  [ValidateSet("dev-preview", "desktop-only", "web-control-plane-preview", "supervisor-heartbeat-preview", "resident-polling-preview", "full-local-preview")]
  [string]$Profile = "dev-preview",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\launch-profiles"

function Test-UnsafeProductText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeProductJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $jsonText = $Value | ConvertTo-Json -Depth 20
  if (Test-UnsafeProductText $jsonText) { throw "Refusing unsafe product profile JSON." }
  Set-Content -LiteralPath $Path -Value $jsonText -Encoding utf8
}

function Write-SafeProductMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeProductText $text) { throw "Refusing unsafe product profile Markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function New-Profile([string]$Name) {
  $commands = @{
    "dev-preview" = @("desktop-preview", "web-preview", "server-preview")
    "desktop-only" = @("desktop-preview")
    "web-control-plane-preview" = @("web-preview", "server-preview")
    "supervisor-heartbeat-preview" = @("supervisor-preview")
    "resident-polling-preview" = @("resident-polling-preview")
    "full-local-preview" = @("desktop-preview", "web-preview", "server-preview", "supervisor-preview", "resident-polling-preview")
  }
  [pscustomobject]@{
    schema = "skybridge.product_profile.v1"
    profile = $Name
    mode = "preview_only"
    commands = $commands[$Name]
    default_command = "launch-preview"
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    trusted_docs_auto_merge_enabled = $false
    global_trusted_docs_auto_merge_enabled = $false
    writes_host_state = $false
    starts_worker_loop = $false
    creates_workunit = $false
    creates_task = $false
    claims_task = $false
    stores_secrets = $false
    report_dir = ".agent/tmp/launch-profiles"
    token_printed = $false
  }
}

function Get-Profiles {
  @(
    "dev-preview",
    "desktop-only",
    "web-control-plane-preview",
    "supervisor-heartbeat-preview",
    "resident-polling-preview",
    "full-local-preview"
  ) | ForEach-Object { New-Profile $_ }
}

function Test-Profile($Item) {
  $errors = @()
  foreach ($key in @("execution_enabled", "queue_apply_enabled", "remote_execution_enabled", "arbitrary_command_enabled", "trusted_docs_auto_merge_enabled", "global_trusted_docs_auto_merge_enabled", "token_printed")) {
    if ($Item.$key -ne $false) { $errors += "$key must be false" }
  }
  if ($Item.mode -ne "preview_only") { $errors += "mode must be preview_only" }
  if ($Item.writes_host_state -ne $false) { $errors += "writes_host_state must be false" }
  [pscustomobject]@{
    schema = "skybridge.product_profile_validation.v1"
    profile = $Item.profile
    ok = (@($errors).Count -eq 0)
    errors = @($errors)
    token_printed = $false
  }
}

function New-ProfileReport {
  $profiles = @(Get-Profiles)
  $validations = @($profiles | ForEach-Object { Test-Profile $_ })
  $report = [pscustomobject]@{
    schema = "skybridge.product_profile_report.v1"
    profile_count = $profiles.Count
    profiles = $profiles
    validations = $validations
    ok = (-not ($validations | Where-Object { $_.ok -ne $true }))
    disabled_capabilities = @("execution", "queue_apply", "remote_execution", "arbitrary_command_dispatch", "global_trusted_docs_auto_merge")
    token_printed = $false
  }
  Write-SafeProductJson (Join-Path $ReportDir "product-profile-report.json") $report
  Write-SafeProductMarkdown (Join-Path $ReportDir "product-profile-report.md") @(
    "# Product Profile Report",
    "",
    "- schema: skybridge.product_profile_report.v1",
    "- profile_count: $($profiles.Count)",
    "- ok: $($report.ok.ToString().ToLowerInvariant())",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- trusted_docs_auto_merge_enabled=false",
    "- token_printed=false"
  )
  $report
}

$result = switch ($Command) {
  "profile-list" { [pscustomobject]@{ schema = "skybridge.product_profile_list.v1"; profiles = @(Get-Profiles); token_printed = $false } }
  "profile-show" { New-Profile $Profile }
  "profile-validate" { Test-Profile (New-Profile $Profile) }
  "safe-summary" { [pscustomobject]@{ ok = $true; profiles = @((Get-Profiles).profile); execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false } }
  "report" { New-ProfileReport }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
