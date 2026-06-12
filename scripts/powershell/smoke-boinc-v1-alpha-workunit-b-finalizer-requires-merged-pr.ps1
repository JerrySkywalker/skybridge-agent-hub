$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-finalizer-preview -SimulateWorkunitAFinalized -SimulateWorkunitBExecuted -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.can_apply -eq $true) { throw "Workunit B finalizer must not apply before merged PR" }
if (-not (@($json.blockers) -contains "workunit_b_pr_missing")) { throw "missing Workunit B PR merge blocker" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-finalizer-requires-merged-pr"; token_printed = $false } | ConvertTo-Json -Compress
