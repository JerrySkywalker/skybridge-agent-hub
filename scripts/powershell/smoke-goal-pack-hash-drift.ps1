[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "hash-drift"
Invoke-GoalPackHelper -Arguments @("-Command", "manifest-update", "-GoalPackDir", $fixture, "-Apply") | Out-Null
Add-Content -LiteralPath (Join-Path $fixture "super-195-manual-goal-queue-management.md") -Value "`n<!-- fixture hash drift -->"
$result = Invoke-GoalPackHelper -Arguments @("-Command", "validate", "-GoalPackDir", $fixture)
if ($result.hash_drift_count -lt 1) { throw "Expected hash drift to be reported." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; hash_drift_count = $result.hash_drift_count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
