[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [switch]$RequireSecondGate,
  [switch]$AllowServerToolExecution,
  [string]$HermesEnvFile,
  [string]$ApiKeyEnvVar = "HERMES_API_KEY",
  [string]$FixtureFile,
  [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"

function Get-EnvValue {
  param([string]$Name)
  return [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-NestedValue {
  param($Object, [string[]]$Path)
  $cursor = $Object
  foreach ($part in $Path) {
    if ($null -eq $cursor) { return $null }
    $prop = $cursor.PSObject.Properties[$part]
    if ($null -eq $prop) { return $null }
    $cursor = $prop.Value
  }
  return $cursor
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function ConvertTo-SafeBool {
  param($Value)
  if ($null -eq $Value) { return $false }
  $text = ([string]$Value).Trim().ToLowerInvariant()
  return @("1", "true", "yes", "y", "configured", "ready", "enabled", "ok") -contains $text
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
  $safe = $safe -replace "https?://[^\s'`"]+", "[redacted-url]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return $safe.Substring(0, $MaxLength) }
  return $safe
}

function ConvertTo-EndpointSummary {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  try {
    $uri = [System.Uri]::new($Value.Trim())
    return "$($uri.Scheme)://[redacted-host]"
  } catch {
    return "[redacted-endpoint]"
  }
}

function Add-Unique {
  param([System.Collections.Generic.List[string]]$List, [string]$Value)
  if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) { $List.Add($Value) }
}

function Import-HermesEnv {
  if ($FixtureFile) { return }
  if ($HermesEnvFile) {
    if (-not (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf)) { throw "Hermes env file not found: $HermesEnvFile" }
    . $HermesEnvFile
    return
  }
  $loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
  if (Test-Path -LiteralPath $loader -PathType Leaf) { . $loader | Out-Null }
}

function Get-SecondGateState {
  $ipAllowlist = ConvertTo-SafeBool (Get-EnvValue "HERMES_SECOND_GATE_IP_ALLOWLIST_CONFIGURED")
  $internalHeader = ConvertTo-SafeBool (Get-EnvValue "HERMES_SECOND_GATE_SHARED_INTERNAL_HEADER_CONFIGURED")
  $endpointAllowlist = ConvertTo-SafeBool (Get-EnvValue "HERMES_SECOND_GATE_ENDPOINT_ALLOWLIST_CONFIGURED")
  $lowPrivilegeToken = ConvertTo-SafeBool (Get-EnvValue "HERMES_SECOND_GATE_LOW_PRIVILEGE_TOKEN_CONFIGURED")
  $configured = $ipAllowlist -or $internalHeader -or $endpointAllowlist -or $lowPrivilegeToken
  [pscustomobject]@{
    configured = $configured
    ip_allowlist = $ipAllowlist
    shared_internal_header = $internalHeader
    endpoint_specific_allowlist = $endpointAllowlist
    separate_low_privilege_token = $lowPrivilegeToken
    token_printed = $false
  }
}

Import-HermesEnv

$apiBaseValue = if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { $ApiBase.Trim() } else { (Get-EnvValue "HERMES_API_BASE") }
$apiKey = Get-EnvValue $ApiKeyEnvVar
$apiBaseConfigured = -not [string]::IsNullOrWhiteSpace($apiBaseValue)
$apiKeyConfigured = -not [string]::IsNullOrWhiteSpace($apiKey)
$endpointRedacted = ConvertTo-EndpointSummary -Value $apiBaseValue
$httpsOnly = $false
if ($apiBaseConfigured) {
  try {
    $uri = [System.Uri]::new($apiBaseValue)
    $httpsOnly = $uri.IsAbsoluteUri -and $uri.Scheme -eq "https"
  } catch {
    $httpsOnly = $false
  }
}

$blockers = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if (-not $apiBaseConfigured) { Add-Unique $blockers "hermes_api_base_missing" }
if (-not $apiKeyConfigured -and -not $FixtureFile) { Add-Unique $blockers "hermes_api_key_missing" }
if ($apiBaseConfigured -and -not $httpsOnly) { Add-Unique $blockers "hermes_https_required" }

$capabilities = $null
$capabilityError = $null
if ($FixtureFile) {
  $capabilities = Read-JsonFile -Path $FixtureFile
} elseif ($apiBaseConfigured -and $apiKeyConfigured) {
  try {
    $headers = @{ Authorization = "Bearer $apiKey" }
    $capabilities = Invoke-RestMethod -Method Get -Uri "$($apiBaseValue.TrimEnd('/'))/v1/capabilities" -Headers $headers -TimeoutSec $TimeoutSeconds
  } catch {
    $capabilityError = ConvertTo-SafeText -Text $_.Exception.Message
  }
}

$capabilitiesReachable = ($null -ne $capabilities)
if (-not $capabilitiesReachable -and $apiBaseConfigured -and ($apiKeyConfigured -or $FixtureFile)) {
  Add-Unique $blockers "hermes_capabilities_unreachable"
}

$runtimeMode = Get-NestedValue -Object $capabilities -Path @("runtime", "mode")
$toolExecution = Get-NestedValue -Object $capabilities -Path @("runtime", "tool_execution")
$responsesApi = Get-NestedValue -Object $capabilities -Path @("features", "responses_api")
$runsApi = Get-NestedValue -Object $capabilities -Path @("features", "runs")
$platform = Get-Prop -Object $capabilities -Name "platform"
$model = Get-Prop -Object $capabilities -Name "model"
if ($null -eq $model -and -not [string]::IsNullOrWhiteSpace($env:HERMES_MODEL)) { $model = $env:HERMES_MODEL }

$serverToolExecution = ($null -ne $toolExecution -and [string]$toolExecution -ne "disabled")
$secondGate = Get-SecondGateState
if ($serverToolExecution) {
  Add-Unique $warnings "hermes_server_tool_execution_enabled"
  if ($RequireSecondGate -and -not $secondGate.configured) {
    Add-Unique $blockers "hermes_second_gate_required_for_server_tool_execution"
  }
}
if ($responsesApi -ne $true) { Add-Unique $warnings "hermes_responses_api_not_confirmed" }
if ($runsApi -eq $true) { Add-Unique $warnings "hermes_runs_api_available" }

$allowHeartbeat = $capabilitiesReachable -and $httpsOnly -and $apiKeyConfigured -and (
  -not $serverToolExecution -or $AllowServerToolExecution.IsPresent
)
$allowExecution = $capabilitiesReachable -and $httpsOnly -and $apiKeyConfigured -and
  (-not $serverToolExecution -or ($RequireSecondGate.IsPresent -and $secondGate.configured)) -and
  ($blockers.Count -eq 0)

$riskLevel = if ($serverToolExecution -or ($blockers.Count -gt 0 -and (@($blockers.ToArray()) -contains "hermes_https_required"))) {
  "high"
} elseif ($warnings.Count -gt 0 -or $blockers.Count -gt 0) {
  "medium"
} else {
  "low"
}
$status = if ($blockers.Count -gt 0) {
  "blocked"
} elseif ($warnings.Count -gt 0) {
  "warning"
} else {
  "ok"
}

$recommended = if (@($blockers.ToArray()) -contains "hermes_api_base_missing") {
  "Configure HERMES_API_BASE in the local Hermes env file and rerun the read-only audit."
} elseif (@($blockers.ToArray()) -contains "hermes_api_key_missing") {
  "Configure HERMES_API_KEY in the local Hermes env file without printing it, then rerun the audit."
} elseif (@($blockers.ToArray()) -contains "hermes_https_required") {
  "Use an HTTPS Hermes API endpoint before any escalation or worker exposure."
} elseif ($serverToolExecution -and -not $secondGate.configured) {
  "Keep start-one and run-until-hold blocked; add a documented second gate before execution-class actions."
} elseif ($allowHeartbeat -and -not $allowExecution) {
  "Heartbeat-only readiness may proceed only under an explicit operator goal; task execution remains blocked."
} else {
  "Continue with read-only monitoring; do not send live escalation or start workers without an explicit goal."
}

$result = [pscustomobject]@{
  schema = "skybridge.hermes_exposure_readiness.v1"
  ok = ($status -ne "blocked")
  status = $status
  risk_level = $riskLevel
  blockers = @($blockers.ToArray())
  warnings = @($warnings.ToArray())
  recommended_next_safe_action = $recommended
  allow_worker_heartbeat = [bool]$allowHeartbeat
  allow_start_one = [bool]$allowExecution
  allow_run_until_hold = [bool]$allowExecution
  hermes = [pscustomobject]@{
    api_base_configured = [bool]$apiBaseConfigured
    api_key_configured = [bool]$apiKeyConfigured
    endpoint = $endpointRedacted
    endpoint_redacted = ($null -ne $endpointRedacted -and $endpointRedacted -notmatch "[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    https_only = [bool]$httpsOnly
    capabilities_reachable = [bool]$capabilitiesReachable
    platform = $platform
    model = $model
    runtime_mode = $runtimeMode
    tool_execution = $toolExecution
    responses_api = $responsesApi
    runs = $runsApi
    error_summary = $capabilityError
    token_printed = $false
  }
  second_gate = $secondGate
  safety = [pscustomobject]@{
    read_only = $true
    real_send_performed = $false
    worker_started = $false
    codex_task_run = $false
    raw_response_included = $false
    credential_values_exposed = $false
    endpoint_redacted = ($null -eq $endpointRedacted -or $endpointRedacted -notmatch [regex]::Escape([string]$apiBaseValue))
    token_printed = $false
  }
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 16
} else {
  "Schema:            $($result.schema)"
  "Status:            $($result.status)"
  "RiskLevel:         $($result.risk_level)"
  "HermesConfigured:  base=$($result.hermes.api_base_configured) key=$($result.hermes.api_key_configured)"
  "Endpoint:          $($result.hermes.endpoint)"
  "HttpsOnly:         $($result.hermes.https_only)"
  "Capabilities:      $($result.hermes.capabilities_reachable)"
  "RuntimeMode:       $($result.hermes.runtime_mode)"
  "ToolExecution:     $($result.hermes.tool_execution)"
  "ResponsesApi:      $($result.hermes.responses_api)"
  "RunsApi:           $($result.hermes.runs)"
  "AllowHeartbeat:    $($result.allow_worker_heartbeat)"
  "AllowStartOne:     $($result.allow_start_one)"
  "AllowUntilHold:    $($result.allow_run_until_hold)"
  "Blockers:          $(if ($result.blockers.Count -gt 0) { $result.blockers -join ', ' } else { 'none' })"
  "Warnings:          $(if ($result.warnings.Count -gt 0) { $result.warnings -join ', ' } else { 'none' })"
  "Next:              $($result.recommended_next_safe_action)"
  "TokenPrinted:      false"
}
