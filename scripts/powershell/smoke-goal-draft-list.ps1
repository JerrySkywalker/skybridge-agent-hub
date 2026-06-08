[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-fixture -Fixture safe -Apply -Json | Out-Null
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-list -Json | ConvertFrom-Json
if (-not $result.ok -or $result.proposed_goal_count -lt 1) { throw "Expected at least one proposed goal." }
if (@($result.proposed_goals | Where-Object { $_.proposed_markdown_path -like "goals/proposed/*" }).Count -lt 1) { throw "Expected goals/proposed path in list." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-list"; count = $result.proposed_goal_count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
