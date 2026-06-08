[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$existing = New-GoalPackSmokeFixture -Name "reimport-existing"
$revised = New-GoalPackSmokeFixture -Name "reimport-revised"
Invoke-GoalPackHelper -Arguments @("-Command", "manifest-update", "-GoalPackDir", $existing, "-Apply") | Out-Null
Invoke-GoalPackHelper -Arguments @("-Command", "manifest-update", "-GoalPackDir", $revised, "-Apply") | Out-Null
Add-Content -LiteralPath (Join-Path $revised "super-195-manual-goal-queue-management.md") -Value "`n<!-- fixture revised goal -->"
$result = Invoke-GoalPackHelper -Arguments @("-Command", "reimport-preview", "-GoalPackDir", $revised, "-ExistingManifestFile", (Join-Path $existing "campaign.skybridge.json"))
if ($result.mode -ne "dry-run") { throw "Re-import preview must be dry-run." }
if (@($result.changed_goals).Count -lt 1) { throw "Expected changed goal in re-import preview." }
if ($result.proposed_action -eq "apply") { throw "Re-import preview must not apply." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; changed_goals = @($result.changed_goals).Count; update_safe = $result.update_safe; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
