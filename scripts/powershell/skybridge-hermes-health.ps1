[CmdletBinding()]
param(
  [string]$HermesApiBase,
  [string]$HermesEnvFile,
  [string]$ApiKeyEnvVar = "HERMES_API_KEY",
  [switch]$Json,
  [string]$OutputFile,
  [int]$TimeoutSeconds = 30,
  [switch]$NoPrintSecrets,
  [string]$FixtureFile
)

$ErrorActionPreference = "Stop"

function Get-EnvValue {
  param([string]$Name)
  return [Environment]::GetEnvironmentVariable($Name, "Process")
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

if ($HermesEnvFile) {
  if (-not (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf)) { throw "Hermes env file not found: $HermesEnvFile" }
  . $HermesEnvFile
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "load-hermes-env.ps1") -PathType Leaf) {
  . (Join-Path $PSScriptRoot "load-hermes-env.ps1")
}

$apiBase = if (-not [string]::IsNullOrWhiteSpace($HermesApiBase)) { $HermesApiBase } else { Get-EnvValue "HERMES_API_BASE" }
$apiKey = Get-EnvValue $ApiKeyEnvVar

if ([string]::IsNullOrWhiteSpace($apiBase)) { throw "HERMES_API_BASE is missing. Supply -HermesApiBase or -HermesEnvFile." }
if ([string]::IsNullOrWhiteSpace($apiKey) -and -not $FixtureFile) { throw "$ApiKeyEnvVar is missing or empty." }

$capabilities = $null
if ($FixtureFile) {
  if (-not (Test-Path -LiteralPath $FixtureFile -PathType Leaf)) { throw "Fixture file not found: $FixtureFile" }
  $capabilities = Get-Content -Raw -LiteralPath $FixtureFile | ConvertFrom-Json
} else {
  $headers = @{ Authorization = "Bearer $apiKey" }
  $capabilities = Invoke-RestMethod -Method Get -Uri "$($apiBase.TrimEnd('/'))/v1/capabilities" -Headers $headers -TimeoutSec $TimeoutSeconds
}

$runtime = Get-NestedValue -Object $capabilities -Path @("runtime")
$features = Get-NestedValue -Object $capabilities -Path @("features")
$result = [pscustomobject]@{
  ok = $true
  api_base = $apiBase
  direct_https = $apiBase -match "^https://"
  key_length = if ($apiKey) { $apiKey.Length } else { 0 }
  platform = Get-NestedValue -Object $capabilities -Path @("platform")
  model = if ((Get-NestedValue -Object $capabilities -Path @("model"))) { Get-NestedValue -Object $capabilities -Path @("model") } elseif ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { $null }
  runtime = [pscustomobject]@{
    mode = if ($runtime) { Get-NestedValue -Object $runtime -Path @("mode") } else { $null }
    tool_execution = if ($runtime) { Get-NestedValue -Object $runtime -Path @("tool_execution") } else { $null }
  }
  features = [pscustomobject]@{
    responses_api = if ($features) { [bool](Get-NestedValue -Object $features -Path @("responses_api")) } else { $null }
    runs = if ($features) { [bool](Get-NestedValue -Object $features -Path @("runs")) } else { $null }
  }
  token_printed = $false
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $result | ConvertTo-Json -Depth 12 -Compress
} else {
  "HermesApiBase: $($result.api_base)"
  "DirectHttps:   $($result.direct_https)"
  "KeyLength:     $($result.key_length)"
  "Platform:      $($result.platform)"
  "Model:         $($result.model)"
  "RuntimeMode:   $($result.runtime.mode)"
  "ToolExec:      $($result.runtime.tool_execution)"
  "ResponsesApi:  $($result.features.responses_api)"
  "Runs:          $($result.features.runs)"
  "TokenPrinted:  false"
}
