$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command blocked-state -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.general_apply_enabled -ne $false -or $json.workunit_b_apply_enabled -ne $false) { throw "general apply or Workunit B apply enabled" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-no-general-apply"; token_printed = $false } | ConvertTo-Json -Compress
