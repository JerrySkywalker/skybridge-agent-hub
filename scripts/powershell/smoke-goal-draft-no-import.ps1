[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | ConvertFrom-Json
if ($result.imported -or $result.validation.imported) { throw "Draft preview imported a goal." }
$campaign = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\goals\dev-queue-189-200\campaign.skybridge.json")
if ($campaign -match "proposed-goal-201-local-readme-refresh") { throw "Campaign manifest contains proposed goal id." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-no-import"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
