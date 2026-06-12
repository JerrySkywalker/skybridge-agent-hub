$ErrorActionPreference = "Stop"
$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-managed-mode-pilot.ps1") -Command safe-summary -Json
$json = ($raw | Out-String).Trim() | ConvertFrom-Json
if ($json.token_printed -ne $false) { throw "token_printed=true" }
if ($json.PSObject.Properties.Name -notcontains "schema") { throw "missing schema" }
[pscustomobject]@{ ok = $true; scenario = "wrapper-managed-mode-pilot-compat"; token_printed = $false } | ConvertTo-Json -Compress
