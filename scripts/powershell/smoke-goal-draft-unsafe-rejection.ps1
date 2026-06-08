[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-fixture -Fixture unsafe -Json | ConvertFrom-Json
if ($result.ok -or $result.wrote) { throw "Unsafe fixture must be rejected and not written." }
if ($result.validation.safety_classification -ne "blocked") { throw "Unsafe fixture must be blocked." }
if (@($result.validation.blocked_reasons).Count -eq 0) { throw "Expected blocked reasons." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-unsafe-rejection"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
