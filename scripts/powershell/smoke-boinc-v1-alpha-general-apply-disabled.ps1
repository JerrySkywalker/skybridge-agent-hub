$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-completion-readiness -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.general_apply_enabled -ne $false) { throw "general bounded queue apply is enabled" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-general-apply-disabled"; token_printed = $false } | ConvertTo-Json -Compress
