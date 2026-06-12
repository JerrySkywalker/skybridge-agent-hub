$text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1")
if ($text -match '(?im)^\s*powercfg(\.exe)?\b|Start-Process\s+["'']?powercfg') { throw "Resource policy must not invoke powercfg." }
. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-ac-ok"
if ($gate.no_powercfg_mutation -ne $true) { throw "Expected no_powercfg_mutation=true." }
Write-LocalResourceSmokeResult "local-resource-enforcement-no-powercfg-mutation"
