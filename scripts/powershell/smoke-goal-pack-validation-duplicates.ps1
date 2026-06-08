[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "duplicates"
$manifestPath = Join-Path $fixture "campaign.skybridge.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$manifest.goals = @($manifest.goals[0], $manifest.goals[0]) + @($manifest.goals | Select-Object -Skip 1)
$manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$result = Invoke-GoalPackHelper -Arguments @("-Command", "validate", "-GoalPackDir", $fixture)
if ($result.ok -ne $false) { throw "Duplicate validation should fail." }
$joined = @($result.errors) -join "`n"
if ($joined -notmatch "duplicate goal id" -or $joined -notmatch "duplicate order") { throw "Duplicate id/order errors not reported." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; duplicate_errors = @($result.errors).Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
