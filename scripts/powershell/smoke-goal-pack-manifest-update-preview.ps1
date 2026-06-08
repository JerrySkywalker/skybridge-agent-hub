[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "manifest-update-preview"
$manifestPath = Join-Path $fixture "campaign.skybridge.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$manifest.goals = @($manifest.goals | ForEach-Object { [pscustomobject]@{ path = $_.path } })
$manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$result = Invoke-GoalPackHelper -Arguments @("-Command", "manifest-preview", "-GoalPackDir", $fixture)
if ($result.mode -ne "dry-run" -or $result.default_dry_run -ne $true) { throw "Manifest preview must be dry-run by default." }
if ($result.update_count -lt 1) { throw "Expected manifest preview to show missing hash updates." }
Assert-NoExecutionResult $result

$summary = [pscustomobject]@{ ok = $true; update_count = $result.update_count; mode = $result.mode; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
