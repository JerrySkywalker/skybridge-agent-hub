$ErrorActionPreference = "Stop"
$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command fixture-ac-ok -Json
$json = ($raw | Out-String).Trim() | ConvertFrom-Json
if ($json.token_printed -ne $false -or $json.can_run_one_at_a_time -ne $true) { throw "unexpected resource fixture" }
[pscustomobject]@{ ok = $true; scenario = "wrapper-local-resource-policy-compat"; token_printed = $false } | ConvertTo-Json -Compress
