$ErrorActionPreference = "Stop"
$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-preview.ps1") -Command status -Json
$json = ($raw | Out-String).Trim() | ConvertFrom-Json
if ($json.token_printed -ne $false -or $json.apply_gate.apply_enabled -ne $false) { throw "unexpected boinc status" }
[pscustomobject]@{ ok = $true; scenario = "wrapper-boinc-v1-preview-compat"; token_printed = $false } | ConvertTo-Json -Compress
