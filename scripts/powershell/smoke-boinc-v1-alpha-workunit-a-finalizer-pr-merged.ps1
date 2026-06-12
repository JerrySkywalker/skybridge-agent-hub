$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-a-finalizer-preview -SimulatePr157Merged -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.pr_merged -ne $true -or $json.human_review_confirmed -ne $true) { throw "Workunit A PR merge was not recognized." }
if ($json.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-a-finalizer-pr-merged"; token_printed = $false } | ConvertTo-Json -Compress
