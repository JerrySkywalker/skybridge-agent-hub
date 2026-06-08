[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$safe = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Fixture safe -Json | ConvertFrom-Json
$medium = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Fixture medium -Json | ConvertFrom-Json
if ($safe.validation.safety_classification -ne "low") { throw "Safe fixture did not classify low." }
if ($medium.validation.safety_classification -ne "medium" -or $medium.draft.review_status -ne "needs_review") { throw "Medium fixture did not require review." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-safety-filter"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
