[CmdletBinding()]
param(
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [int]$TimeoutSeconds = 30,
  [switch]$Json,
  [string]$OutputFile,
  [string]$FixtureFile,
  [string]$FixtureHermesHealthFile
)

$ErrorActionPreference = "Stop"

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function ConvertTo-SafeText {
  param([string]$Text, [int]$MaxLength = 220)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key|webhook)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Invoke-ChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -ne 0 -and -not $AllowNonZero) {
    throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)"
  }
  if ($null -ne $parsed) { return $parsed }
  if ($exitCode -ne 0) { throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)" }
  throw "Command did not return JSON: pwsh $($Arguments -join ' ')"
}

function ConvertTo-SafeBool {
  param($Value)
  if ($null -eq $Value) { return $false }
  $text = ([string]$Value).Trim().ToLowerInvariant()
  return @("1", "true", "yes", "y", "configured", "ready", "enabled", "ok") -contains $text
}

function Get-SafeEnvBool {
  param([string[]]$Names)
  foreach ($name in $Names) {
    $value = [Environment]::GetEnvironmentVariable($name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return ConvertTo-SafeBool -Value $value
    }
  }
  return $false
}

function Test-BootstrapNotifierDryRunAvailable {
  $path = Join-Path $PSScriptRoot "notify-bootstrap.ps1"
  return (Test-Path -LiteralPath $path -PathType Leaf)
}

function Get-HermesHealth {
  if ($FixtureHermesHealthFile) {
    return Read-JsonFile -Path $FixtureHermesHealthFile
  }

  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-hermes-health.ps1"),
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
  if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
  return Invoke-ChildJson -Arguments $args
}

if ($FixtureFile) {
  $fixture = Read-JsonFile -Path $FixtureFile
  $realProviderReady = [bool](Get-Prop -Object $fixture -Name "real_provider_ready" -Default (Get-Prop -Object $fixture -Name "can_send_real_blocker_notice" -Default (Get-Prop -Object $fixture -Name "can_send_blocker_notice" -Default $false)))
  $bootstrapDryRunAvailable = [bool](Get-Prop -Object $fixture -Name "bootstrap_dry_run_available" -Default (Test-BootstrapNotifierDryRunAvailable))
  $blockerNoticeSupported = [bool](Get-Prop -Object $fixture -Name "blocker_notice_supported" -Default ($realProviderReady -or $bootstrapDryRunAvailable))
  $readinessMode = if ($realProviderReady) { "real_provider_ready" } elseif ($bootstrapDryRunAvailable) { "bootstrap_dry_run_available" } else { "unavailable" }
  $result = [pscustomobject]@{
    schema = "skybridge.admin_escalation_readiness.v1"
    ok = [bool](Get-Prop -Object $fixture -Name "ok" -Default $blockerNoticeSupported)
    readiness_mode = [string](Get-Prop -Object $fixture -Name "readiness_mode" -Default $readinessMode)
    primary_current = [string](Get-Prop -Object $fixture -Name "primary_current" -Default "hermes-wechat")
    long_term_primary = [string](Get-Prop -Object $fixture -Name "long_term_primary" -Default "skybridge-notify-gateway")
    fallback = [string](Get-Prop -Object $fixture -Name "fallback" -Default "bootstrap-notifier")
    hermes_available = [bool](Get-Prop -Object $fixture -Name "hermes_available" -Default $false)
    hermes_direct_https = [bool](Get-Prop -Object $fixture -Name "hermes_direct_https" -Default $false)
    hermes_platform = Get-Prop -Object $fixture -Name "hermes_platform"
    hermes_runtime_mode = Get-Prop -Object $fixture -Name "hermes_runtime_mode"
    hermes_responses_api = [bool](Get-Prop -Object $fixture -Name "hermes_responses_api" -Default $false)
    wechat_escalation_configured = [bool](Get-Prop -Object $fixture -Name "wechat_escalation_configured" -Default $false)
    can_send_real_blocker_notice = $realProviderReady
    real_provider_ready = $realProviderReady
    bootstrap_dry_run_available = $bootstrapDryRunAvailable
    blocker_notice_supported = $blockerNoticeSupported
    can_send_blocker_notice = $blockerNoticeSupported
    dry_run_supported = [bool](Get-Prop -Object $fixture -Name "dry_run_supported" -Default $true)
    real_send_performed = [bool](Get-Prop -Object $fixture -Name "real_send_performed" -Default $false)
    credential_values_exposed = [bool](Get-Prop -Object $fixture -Name "credential_values_exposed" -Default $false)
    raw_response_included = [bool](Get-Prop -Object $fixture -Name "raw_response_included" -Default $false)
    token_printed = [bool](Get-Prop -Object $fixture -Name "token_printed" -Default $false)
  }
} else {
  $health = $null
  $healthError = $null
  try {
    $health = Get-HermesHealth
  } catch {
    $healthError = ConvertTo-SafeText -Text $_.Exception.Message
  }

  $runtime = Get-Prop -Object $health -Name "runtime"
  $features = Get-Prop -Object $health -Name "features"
  $hermesAvailable = ($null -ne $health -and [bool](Get-Prop -Object $health -Name "ok" -Default $false))
  $hermesDirectHttps = ($null -ne $health -and [bool](Get-Prop -Object $health -Name "direct_https" -Default $false))
  $responsesApi = if ($features) { [bool](Get-Prop -Object $features -Name "responses_api" -Default $false) } else { $false }
  $wechatConfigured = Get-SafeEnvBool -Names @(
    "SKYBRIDGE_ADMIN_ESCALATION_WECHAT_CONFIGURED",
    "HERMES_WECHAT_ESCALATION_CONFIGURED",
    "HERMES_WECOM_ESCALATION_CONFIGURED"
  )
  $canSend = ($hermesAvailable -and $hermesDirectHttps -and $responsesApi -and $wechatConfigured)
  $bootstrapDryRunAvailable = Test-BootstrapNotifierDryRunAvailable
  $blockerNoticeSupported = ($canSend -or $bootstrapDryRunAvailable)

  $result = [pscustomobject]@{
    schema = "skybridge.admin_escalation_readiness.v1"
    ok = $blockerNoticeSupported
    readiness_mode = if ($canSend) { "real_provider_ready" } elseif ($bootstrapDryRunAvailable) { "bootstrap_dry_run_available" } else { "unavailable" }
    primary_current = "hermes-wechat"
    long_term_primary = "skybridge-notify-gateway"
    fallback = "bootstrap-notifier"
    hermes_available = $hermesAvailable
    hermes_direct_https = $hermesDirectHttps
    hermes_platform = Get-Prop -Object $health -Name "platform"
    hermes_runtime_mode = Get-Prop -Object $runtime -Name "mode"
    hermes_responses_api = $responsesApi
    wechat_escalation_configured = $wechatConfigured
    can_send_real_blocker_notice = $canSend
    real_provider_ready = $canSend
    bootstrap_dry_run_available = $bootstrapDryRunAvailable
    blocker_notice_supported = $blockerNoticeSupported
    can_send_blocker_notice = $blockerNoticeSupported
    dry_run_supported = $true
    real_send_performed = $false
    credential_values_exposed = $false
    raw_response_included = $false
    error_summary = $healthError
    token_printed = $false
  }
}

if ($result.real_send_performed -or $result.credential_values_exposed -or $result.raw_response_included -or $result.token_printed) {
  $result.ok = $false
  $result.can_send_blocker_notice = $false
  $result.blocker_notice_supported = $false
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $result | ConvertTo-Json -Depth 12
} else {
  "Schema:            $($result.schema)"
  "Ok:                $($result.ok)"
  "PrimaryCurrent:    $($result.primary_current)"
  "LongTermPrimary:   $($result.long_term_primary)"
  "Fallback:          $($result.fallback)"
  "HermesAvailable:   $($result.hermes_available)"
  "HermesDirectHttps: $($result.hermes_direct_https)"
  "HermesPlatform:    $($result.hermes_platform)"
  "HermesRuntimeMode: $($result.hermes_runtime_mode)"
  "HermesResponsesApi:$($result.hermes_responses_api)"
  "WechatConfigured:  $($result.wechat_escalation_configured)"
  "CanBlockerNotice:  $($result.can_send_blocker_notice)"
  "RealNoticeReady:   $($result.can_send_real_blocker_notice)"
  "BootstrapDryRun:   $($result.bootstrap_dry_run_available)"
  "DryRunSupported:   $($result.dry_run_supported)"
  "RealSendPerformed: false"
  "CredentialExposed: false"
  "RawResponse:       false"
  "TokenPrinted:      false"
}
