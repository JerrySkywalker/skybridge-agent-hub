$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-preview -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.policy.schema -ne "skybridge.boinc_v1_alpha_policy.v1") { throw "wrong policy schema" }
if ($json.policy.alpha_id -ne "boinc-v1-alpha-215" -or $json.policy.general_apply_enabled -ne $false) { throw "invalid alpha policy" }
if ($json.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-policy-contract"; token_printed = $false } | ConvertTo-Json -Compress
