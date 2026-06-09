$ErrorActionPreference = "Stop"
$policy = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command preview -Json | ConvertFrom-Json
$json = $policy | ConvertTo-Json -Depth 20 -Compress
if ($json -notmatch '"token_printed":false' -or $json -match 'token_printed"\s*:\s*true') { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "local-resource-policy-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
