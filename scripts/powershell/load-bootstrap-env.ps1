[CmdletBinding()]
param(
  [Alias("Json")]
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$bootstrapVariableNames = @(
  "SKYBRIDGE_BOOTSTRAP_NTFY_URL",
  "SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC",
  "SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC",
  "SKYBRIDGE_BOOTSTRAP_NTFY_USER",
  "SKYBRIDGE_BOOTSTRAP_NTFY_PASS",
  "SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN",
  "SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK"
)

function Get-BootstrapEnvFilePath {
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_BOOTSTRAP_ENV_FILE)) {
    return @{
      path = $env:SKYBRIDGE_BOOTSTRAP_ENV_FILE
      source = "SKYBRIDGE_BOOTSTRAP_ENV_FILE"
    }
  }

  return @{
    path = Join-Path $HOME ".skybridge\bootstrap-notify.env.ps1"
    source = "default"
  }
}

function Get-BootstrapVariableStatus {
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

$file = Get-BootstrapEnvFilePath
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

$status.variables = Get-BootstrapVariableStatus -Names $bootstrapVariableNames
$status.missing = @($status.variables | Where-Object { -not $_.present } | ForEach-Object { $_.name })

if ($AsJson) {
  $status | ConvertTo-Json -Depth 8
}
