$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-apply-gate -AuthorizeGoal215 -SimulateOpenReview -Json | Out-String).Trim() | ConvertFrom-Json
if (@($json.blockers) -notcontains "open_review_hold") { throw "open review hold should block" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-open-review-hold"; token_printed = $false } | ConvertTo-Json -Compress
