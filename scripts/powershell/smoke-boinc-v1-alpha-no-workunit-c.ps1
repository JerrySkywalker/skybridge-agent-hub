$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-completion-readiness -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.workunit_c_present -ne $false -or $json.general_apply_enabled -ne $false) { throw "Workunit C must be absent and general apply disabled" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-no-workunit-c"; token_printed = $false } | ConvertTo-Json -Compress
