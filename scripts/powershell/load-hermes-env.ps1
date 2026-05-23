[CmdletBinding()]
param(
  [Alias("Json")]
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$hermesVariableNames = @(
  "HERMES_API_BASE",
  "HERMES_API_KEY",
  "HERMES_MODEL"
)

function Get-HermesEnvFilePath {
  if (-not [string]::IsNullOrWhiteSpace($env:HERMES_ENV_FILE)) {
    return @{
      path = $env:HERMES_ENV_FILE
      source = "HERMES_ENV_FILE"
    }
  }

  return @{
    path = Join-Path $HOME ".skybridge\hermes.env.ps1"
    source = "default"
  }
}

function Get-HermesVariableStatus {
  param([string[]]$Names)

  $items = @()
  foreach ($name in $Names) {
    $items += @{
      name = $name
      present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, "Process"))
      value_included = $false
    }
  }
  return $items
}

$file = Get-HermesEnvFilePath
$status = @{
  ok = $true
  loaded = $false
  file_exists = $false
  env_file = $file.path
  env_file_source = $file.source
  fail_open = $true
  error = $null
  variables = @()
}

if (Test-Path -LiteralPath $file.path -PathType Leaf) {
  $status.file_exists = $true
  try {
    . $file.path
    $status.loaded = $true
  } catch {
    $status.ok = $false
    $status.error = $_.Exception.Message
  }
}

$status.variables = Get-HermesVariableStatus -Names $hermesVariableNames
$status.present = @($status.variables | Where-Object { $_.present } | ForEach-Object { $_.name })
$status.missing = @($status.variables | Where-Object { -not $_.present } | ForEach-Object { $_.name })

if ($AsJson) {
  $status | ConvertTo-Json -Depth 8
}
