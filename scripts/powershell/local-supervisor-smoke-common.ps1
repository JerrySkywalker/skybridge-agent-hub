$ErrorActionPreference = "Stop"

function Invoke-LocalSupervisorSmokeCommand {
  param([string]$Command)
  $Script = Join-Path $PSScriptRoot "skybridge-local-supervisor.ps1"
  $Json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script -Command $Command -Json | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Local supervisor command failed: $Command"
  }
  if ($Json -match 'token_printed"\s*:\s*true') {
    throw "token_printed=true in $Command"
  }
  if ($Json -match '(Authorization|Bearer\s+|OPENAI_API_KEY|private_key|cookie)') {
    throw "secret-looking text in $Command"
  }
  return $Json | ConvertFrom-Json
}

function Assert-FalseProperty {
  param([object]$Object, [string]$Name)
  if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
    throw "Missing property: $Name"
  }
  if ([bool]$Object.$Name) {
    throw "Expected $Name=false"
  }
}

function Assert-TrueProperty {
  param([object]$Object, [string]$Name)
  if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
    throw "Missing property: $Name"
  }
  if (-not [bool]$Object.$Name) {
    throw "Expected $Name=true"
  }
}
