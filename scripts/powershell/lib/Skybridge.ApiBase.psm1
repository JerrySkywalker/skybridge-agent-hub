$PlaceholderSkyBridgeApiBase = "https://skybridge.example.com"
$PlaceholderMessage = "SkyBridge ApiBase is a placeholder or invalid. Set SKYBRIDGE_API_BASE or pass -ApiBase."
$HermesMistakeMessage = "SKYBRIDGE_API_BASE appears to point to Hermes API. Set it to the SkyBridge Server API base."

function ConvertTo-SkybridgeSafeText {
  param([string]$Text, [int]$MaxLength = 260)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{8,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key|webhook)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe -replace "https?://[^\s'`"]+", "[redacted-url]"
  $safe = $safe -replace "(?i)HERMES_API_KEY", "HERMES_KEY_VAR"
  $safe = $safe -replace "(?i)SKYBRIDGE_WORKER_TOKEN", "SKYBRIDGE_WORKER_VAR"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function Resolve-SkybridgeApiBase {
  param(
    [string]$ApiBase,
    [bool]$ParameterWasBound = $false
  )
  if ($ParameterWasBound -and -not [string]::IsNullOrWhiteSpace($ApiBase)) {
    return $ApiBase.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) {
    return $env:SKYBRIDGE_API_BASE.Trim()
  }
  return $PlaceholderSkyBridgeApiBase
}

function Test-SkybridgeApiBaseInvalid {
  param([string]$ApiBase)
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return $true }
  $trimmed = $ApiBase.Trim()
  if ($trimmed -in @($PlaceholderSkyBridgeApiBase, "<PRIVATE_SKYBRIDGE_API_BASE>")) { return $true }
  if ($trimmed -match "(?i)example\.com/?$") { return $true }
  if ($trimmed -match "^<.*>$") { return $true }
  try {
    $uri = [System.Uri]::new($trimmed)
    if (-not $uri.IsAbsoluteUri) { return $true }
    if ($uri.Scheme -notin @("http", "https")) { return $true }
  } catch {
    return $true
  }
  return $false
}

function Assert-SkybridgeApiBaseUsable {
  param(
    [string]$ApiBase,
    [bool]$AllowPlaceholder = $false
  )
  if ($AllowPlaceholder) { return }
  if (Test-SkybridgeApiBaseInvalid -ApiBase $ApiBase) {
    throw $PlaceholderMessage
  }
}

function Test-SkybridgeVersionLooksHermes {
  param($Version)
  if ($null -eq $Version) { return $false }
  $schema = [string]$Version.schema
  $service = [string]$Version.service
  if ($schema -match "(?i)hermes" -or $service -match "(?i)hermes") { return $true }
  foreach ($name in @("capabilities", "platform", "model", "runtime", "features", "responses_api")) {
    if ($null -ne $Version.PSObject.Properties[$name]) { return $true }
  }
  return $false
}

function Assert-SkybridgeVersionService {
  param($Version)
  if (Test-SkybridgeVersionLooksHermes -Version $Version) {
    throw $HermesMistakeMessage
  }
  if ([string]$Version.schema -ne "skybridge.server_version.v1" -or [string]$Version.service -ne "skybridge-server") {
    throw "SKYBRIDGE_API_BASE does not point to a SkyBridge Server /v1/version endpoint."
  }
}

function Get-SkybridgeVersionMetadata {
  param(
    [string]$ApiBase,
    [int]$TimeoutSeconds = 20
  )
  $uri = $ApiBase.TrimEnd("/") + "/v1/version"
  return Invoke-RestMethod -Uri $uri -Method GET -TimeoutSec $TimeoutSeconds
}

function Assert-SkybridgeApiBaseService {
  param(
    [string]$ApiBase,
    [int]$TimeoutSeconds = 20
  )
  $version = Get-SkybridgeVersionMetadata -ApiBase $ApiBase -TimeoutSeconds $TimeoutSeconds
  Assert-SkybridgeVersionService -Version $version
  return $version
}

Export-ModuleMember -Function ConvertTo-SkybridgeSafeText, Resolve-SkybridgeApiBase, Test-SkybridgeApiBaseInvalid, Assert-SkybridgeApiBaseUsable, Test-SkybridgeVersionLooksHermes, Assert-SkybridgeVersionService, Get-SkybridgeVersionMetadata, Assert-SkybridgeApiBaseService
