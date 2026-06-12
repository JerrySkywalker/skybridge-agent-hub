$ErrorActionPreference = "Stop"
$script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1")
if ($script -match '(?i)powercfg\s+/(change|set|hibernate|setacvalueindex|setdcvalueindex)') { throw "Resource policy script mutates powercfg." }
$policy = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command preview -Json | ConvertFrom-Json
if ($policy.no_powercfg_mutation -ne $true) { throw "Policy preview would mutate powercfg." }
[pscustomobject]@{ ok = $true; scenario = "local-resource-policy-no-powercfg-mutation"; token_printed = $false } | ConvertTo-Json -Compress
