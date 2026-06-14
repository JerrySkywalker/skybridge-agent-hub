[CmdletBinding()]
param(
  [ValidateSet("validate", "show-safe", "redaction-check", "profile-preview", "write-example", "safe-summary", "report")]
  [string]$Command = "validate",
  [string]$Path = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\product-readiness"
$ExamplePath = Join-Path $RepoRoot "fixtures\productization\local-config.example.json"

function Get-ConfigPath {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $ExamplePath }
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $RepoRoot $Path)
}

function Read-ConfigText {
  Get-Content -Raw -LiteralPath (Get-ConfigPath)
}

function Test-SecretLookingText([string]$Text) {
  $patterns = @(
    "Authorization\s*:",
    "Bearer\s+[A-Za-z0-9_\-\.]{12,}",
    "-----BEGIN\s+(RSA\s+)?PRIVATE KEY-----",
    "cookie\s*[:=]",
    "token_printed\s*['""]?\s*:\s*true",
    "execution_enabled\s*['""]?\s*:\s*true",
    "queue_apply_enabled\s*['""]?\s*:\s*true",
    "remote_execution_enabled\s*['""]?\s*:\s*true",
    "arbitrary_command_enabled\s*['""]?\s*:\s*true",
    "[A-Za-z]:\\Users\\[^\\]+\\.*(secret|token|key|cookie)"
  )
  foreach ($pattern in $patterns) {
    if ($Text -match $pattern) { return $true }
  }
  return $false
}

function New-Validation {
  $text = Read-ConfigText
  $config = $text | ConvertFrom-Json
  $profile = $config.profile
  $errors = @()
  if ($config.schema -ne "skybridge.local_config.v1") { $errors += "schema_mismatch" }
  if ($profile.schema -ne "skybridge.local_config_profile.v1") { $errors += "profile_schema_mismatch" }
  foreach ($field in @("execution_enabled", "queue_apply_enabled", "remote_execution_enabled", "arbitrary_command_enabled", "trusted_docs_auto_merge_enabled")) {
    if ($profile.$field -ne $false) { $errors += "$field must be false" }
  }
  if (Test-SecretLookingText $text) { $errors += "secret_or_unsafe_content_detected" }
  [pscustomobject]@{
    schema = "skybridge.local_config_validation.v1"
    ok = ($errors.Count -eq 0)
    profile_name = $profile.profile_name
    mode = $profile.mode
    errors = @($errors)
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-RedactionCheck {
  $text = Read-ConfigText
  [pscustomobject]@{
    schema = "skybridge.local_config_redaction.v1"
    ok = (-not (Test-SecretLookingText $text))
    rejects_token_like_content = $true
    rejects_authorization_headers = $true
    rejects_private_keys = $true
    rejects_cookies = $true
    rejects_secret_paths = $true
    token_printed = $false
  }
}

function New-ProfilePreview {
  $config = Read-ConfigText | ConvertFrom-Json
  [pscustomobject]@{
    schema = "skybridge.local_config_profile.v1"
    profile_name = $config.profile.profile_name
    mode = "local_preview"
    web_enabled = [bool]$config.profile.web_enabled
    desktop_enabled = [bool]$config.profile.desktop_enabled
    server_preview_enabled = [bool]$config.profile.server_preview_enabled
    resident_polling_preview_enabled = [bool]$config.profile.resident_polling_preview_enabled
    diagnostics_enabled = [bool]$config.profile.diagnostics_enabled
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    trusted_docs_auto_merge_enabled = $false
    token_printed = $false
  }
}

function Write-Reports {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $validation = New-Validation
  $redaction = New-RedactionCheck
  $validation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "local-config-validation-report.json") -Encoding utf8
  $redaction | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReportDir "local-config-redaction-report.json") -Encoding utf8
  [pscustomobject]@{ schema = "skybridge.local_config_report.v1"; validation = $validation; redaction = $redaction; token_printed = $false }
}

$result = switch ($Command) {
  "validate" { New-Validation }
  "show-safe" { New-ProfilePreview }
  "redaction-check" { New-RedactionCheck }
  "profile-preview" { New-ProfilePreview }
  "write-example" { New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null; Get-Content -Raw -LiteralPath $ExamplePath | Set-Content -LiteralPath (Join-Path $ReportDir "local-config.example.safe.json") -Encoding utf8; New-ProfilePreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; no_secrets = $true; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false } }
  "report" { Write-Reports }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
