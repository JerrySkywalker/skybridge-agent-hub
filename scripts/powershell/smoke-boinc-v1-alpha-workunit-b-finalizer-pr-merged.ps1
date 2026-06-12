$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-finalizer-preview -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.alpha_id -ne "boinc-v1-alpha-215" -or $json.workunit_id -ne "boinc-v1-alpha-215-workunit-b") { throw "unexpected Workunit B identity" }
if ($json.pr_number -ne 159 -or $json.pr_merged -ne $true -or $json.can_apply -ne $true) { throw "Workunit B PR is not ready for finalizer" }
if ($json.changed_file -ne "docs/boinc-v1-alpha-workunit-b.md" -or $json.human_review_confirmed -ne $true) { throw "Workunit B finalizer PR contract mismatch" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-finalizer-pr-merged"; token_printed = $false } | ConvertTo-Json -Compress
