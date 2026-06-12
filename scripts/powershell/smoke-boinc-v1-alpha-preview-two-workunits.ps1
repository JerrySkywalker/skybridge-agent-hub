$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-preview -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.preview_workunit_count -ne 2 -or @($json.workunits).Count -ne 2) { throw "expected exactly two workunits" }
if (@($json.workunits | Where-Object task_type -ne "docs/local-smoke").Count -gt 0) { throw "expected docs/local-smoke" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-preview-two-workunits"; token_printed = $false } | ConvertTo-Json -Compress
