$ErrorActionPreference = "Stop"
$policy = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command status -Json | ConvertFrom-Json
if ($policy.schema -ne "skybridge.local_resource_policy.v1") { throw "Unexpected policy schema." }
if ($policy.enforcement_status -notin @("enforced", "preview_only")) { throw "Resource policy must report a known enforcement status." }
if ($policy.enforcement_status -ne "enforced") { throw "Resource policy must be enforced for managed-mode run gates." }
if ($policy.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "local-resource-policy-contract"; token_printed = $false } | ConvertTo-Json -Compress
