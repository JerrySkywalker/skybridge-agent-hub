$ErrorActionPreference = "Stop"
$summary = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command safe-summary -Json | ConvertFrom-Json
if (-not $summary.ok -or $summary.no_powercfg_mutation -ne $true) { throw "Safe summary did not confirm no powercfg mutation." }
if ($summary.policy.task_claimed -ne $false -or $summary.policy.task_executed -ne $false) { throw "Resource policy must not claim or execute tasks." }
[pscustomobject]@{ ok = $true; scenario = "local-resource-policy-safe-summary"; token_printed = $false } | ConvertTo-Json -Compress
