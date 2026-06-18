[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Title,

  [Parameter(Mandatory = $true)]
  [string]$Message,

  [ValidateSet("info", "warning", "urgent")]
  [string]$Severity = "warning",

  [switch]$Send,
  [switch]$Json,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [string]$FixtureFile,
  [int]$TimeoutSeconds = 30
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
  param([string]$Text, [int]$MaxLength = 120)
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

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return ($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9._-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|(token|secret|password|cookie|credential|api[_-]?key|webhook)\s*[:=]\s*\S+|-----BEGIN [A-Z ]*PRIVATE KEY-----")
}

function Invoke-ChildJson {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($null -ne $parsed) { return $parsed }
  if ($exitCode -ne 0) { throw "Command failed: pwsh $($Arguments -join ' '): $(ConvertTo-SafeText -Text $text)" }
  throw "Command did not return JSON: pwsh $($Arguments -join ' ')"
}

function Get-EnvValue {
  param([string]$Name)
  return [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Import-HermesEnv {
  if ($HermesEnvFile) {
    if (-not (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf)) { throw "Hermes env file not found: $HermesEnvFile" }
    . $HermesEnvFile
  } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "load-hermes-env.ps1") -PathType Leaf) {
    . (Join-Path $PSScriptRoot "load-hermes-env.ps1")
  }
}

function Get-AdminReadiness {
  param($Fixture)
  $fixtureReadiness = Get-Prop -Object $Fixture -Name "admin_readiness"
  if ($fixtureReadiness) { return $fixtureReadiness }

  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-admin-escalation-readiness.ps1"),
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($HermesEnvFile) { $args += @("-HermesEnvFile", $HermesEnvFile) }
  if ($HermesApiBase) { $args += @("-HermesApiBase", $HermesApiBase) }
  return Invoke-ChildJson -Arguments $args
}

function New-SafeMessage {
  param([string]$Reason)
  [pscustomobject]@{
    project_id = "skybridge-agent-hub"
    environment = "bootstrap-test"
    severity = $Severity
    short_reason = ConvertTo-SafeText -Text $Reason -MaxLength 120
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
  }
}

function New-Result {
  param($Readiness)
  [ordered]@{
    schema = "skybridge.admin_escalation_test.v1"
    ok = $false
    channel = "hermes-wechat"
    dry_run = -not [bool]$Send
    send_requested = [bool]$Send
    send_performed = $false
    would_send = $false
    delivery_status = "not_evaluated"
    delivery_confirmed = $false
    hermes_available = [bool](Get-Prop -Object $Readiness -Name "hermes_available" -Default $false)
    hermes_direct_https = [bool](Get-Prop -Object $Readiness -Name "hermes_direct_https" -Default $false)
    message_redacted = $true
    credential_values_exposed = $false
    raw_response_included = $false
    raw_notification_payload_included = $false
    token_printed = $false
  }
}

function Get-SendEndpointPath {
  param($Fixture)
  $fixturePath = [string](Get-Prop -Object $Fixture -Name "send_endpoint_path" -Default "")
  if (-not [string]::IsNullOrWhiteSpace($fixturePath)) { return $fixturePath }
  $envPath = Get-EnvValue "HERMES_ADMIN_ESCALATION_SEND_PATH"
  if (-not [string]::IsNullOrWhiteSpace($envPath)) { return $envPath }
  return $null
}

function Invoke-FixtureSend {
  param($Fixture)
  $sendResponse = Get-Prop -Object $Fixture -Name "send_response"
  if (-not $sendResponse) {
    return [pscustomobject]@{
      ok = $false
      delivery_status = "fixture_send_response_missing"
      delivery_confirmed = $false
      credential_values_exposed = $false
      raw_response_included = $false
      raw_notification_payload_included = $false
      token_printed = $false
    }
  }
  return $sendResponse
}

function Invoke-HermesAdminSend {
  param([string]$EndpointPath, $Payload)
  Import-HermesEnv
  $apiBase = if (-not [string]::IsNullOrWhiteSpace($HermesApiBase)) { $HermesApiBase } else { Get-EnvValue "HERMES_API_BASE" }
  $apiKey = Get-EnvValue "HERMES_API_KEY"
  if ([string]::IsNullOrWhiteSpace($apiBase) -or [string]::IsNullOrWhiteSpace($apiKey)) {
    return [pscustomobject]@{ ok = $false; delivery_status = "hermes_credentials_missing"; delivery_confirmed = $false }
  }

  $headers = @{ Authorization = "Bearer $apiKey" }
  $uri = "$($apiBase.TrimEnd('/'))/$($EndpointPath.TrimStart('/'))"
  $body = $Payload | ConvertTo-Json -Depth 8 -Compress
  try {
    $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSeconds
    return [pscustomobject]@{
      ok = [bool](Get-Prop -Object $response -Name "ok" -Default $true)
      delivery_status = [string](Get-Prop -Object $response -Name "delivery_status" -Default "sent_unconfirmed")
      delivery_confirmed = [bool](Get-Prop -Object $response -Name "delivery_confirmed" -Default $false)
      credential_values_exposed = [bool](Get-Prop -Object $response -Name "credential_values_exposed" -Default $false)
      raw_response_included = $false
      raw_notification_payload_included = $false
      token_printed = $false
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      delivery_status = "send_failed"
      delivery_confirmed = $false
      credential_values_exposed = $false
      raw_response_included = $false
      raw_notification_payload_included = $false
      token_printed = $false
    }
  }
}

$fixture = $null
if ($FixtureFile) { $fixture = Read-JsonFile -Path $FixtureFile }
$readiness = Get-AdminReadiness -Fixture $fixture
$result = New-Result -Readiness $readiness

$unsafeInput = (Test-UnsafeText -Text $Title) -or (Test-UnsafeText -Text $Message)
$readinessUnsafe = [bool](Get-Prop -Object $readiness -Name "credential_values_exposed" -Default $false) -or
  [bool](Get-Prop -Object $readiness -Name "raw_response_included" -Default $false) -or
  [bool](Get-Prop -Object $readiness -Name "token_printed" -Default $false)

if ($unsafeInput) {
  $result.delivery_status = "blocked_unsafe_message"
} elseif ($readinessUnsafe) {
  $result.delivery_status = "readiness_unsafe"
} elseif (-not [bool](Get-Prop -Object $readiness -Name "ok" -Default $false) -or -not [bool](Get-Prop -Object $readiness -Name "can_send_blocker_notice" -Default $false)) {
  $result.delivery_status = "readiness_unavailable"
} elseif (-not $Send) {
  $safeMessage = New-SafeMessage -Reason $Message
  $null = $safeMessage
  $result.ok = $true
  $result.would_send = $true
  $result.delivery_status = "dry_run"
} else {
  $endpointPath = Get-SendEndpointPath -Fixture $fixture
  if ([string]::IsNullOrWhiteSpace($endpointPath)) {
    $result.delivery_status = "send_endpoint_not_available"
  } else {
    $safeMessage = New-SafeMessage -Reason $Message
    $sendResult = if ($FixtureFile) {
      Invoke-FixtureSend -Fixture $fixture
    } else {
      Invoke-HermesAdminSend -EndpointPath $endpointPath -Payload $safeMessage
    }
    $sendUnsafe = [bool](Get-Prop -Object $sendResult -Name "credential_values_exposed" -Default $false) -or
      [bool](Get-Prop -Object $sendResult -Name "raw_response_included" -Default $false) -or
      [bool](Get-Prop -Object $sendResult -Name "raw_notification_payload_included" -Default $false) -or
      [bool](Get-Prop -Object $sendResult -Name "token_printed" -Default $false)

    $result.send_performed = -not $sendUnsafe -and [bool](Get-Prop -Object $sendResult -Name "ok" -Default $false)
    $result.delivery_status = if ($sendUnsafe) { "blocked_unsafe_response" } else { [string](Get-Prop -Object $sendResult -Name "delivery_status" -Default "sent_unconfirmed") }
    $result.delivery_confirmed = -not $sendUnsafe -and [bool](Get-Prop -Object $sendResult -Name "delivery_confirmed" -Default $false)
    $result.ok = ($result.send_performed -and -not $sendUnsafe)
  }
}

if ($Json) {
  [pscustomobject]$result | ConvertTo-Json -Depth 12
} else {
  "Schema:                 $($result.schema)"
  "Ok:                     $($result.ok)"
  "Channel:                $($result.channel)"
  "DryRun:                 $($result.dry_run)"
  "SendRequested:          $($result.send_requested)"
  "SendPerformed:          $($result.send_performed)"
  "WouldSend:              $($result.would_send)"
  "DeliveryStatus:         $($result.delivery_status)"
  "DeliveryConfirmed:      $($result.delivery_confirmed)"
  "HermesAvailable:        $($result.hermes_available)"
  "HermesDirectHttps:      $($result.hermes_direct_https)"
  "MessageRedacted:        true"
  "CredentialExposed:      false"
  "RawResponseIncluded:    false"
  "RawPayloadIncluded:     false"
  "TokenPrinted:           false"
}

if (-not $result.ok) {
  exit 1
}
