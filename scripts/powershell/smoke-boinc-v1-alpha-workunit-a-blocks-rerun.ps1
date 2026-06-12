$ErrorActionPreference = "Stop"
$script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1")
if ($script -notlike "*Workunit A finalizer already applied*") { throw "missing duplicate Workunit A finalizer guard" }
if ($script -notlike "*workunit_a_rerun_blocked*") { throw "missing Workunit A rerun blocked report field" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-a-blocks-rerun"; token_printed = $false } | ConvertTo-Json -Compress
