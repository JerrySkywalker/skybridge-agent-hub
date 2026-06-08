[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$before = Get-GitShortStatusText
$fixture = New-GoalPackSmokeFixture -Name "no-execution"
$commands = @(
  @("-Command", "validate", "-GoalPackDir", $fixture),
  @("-Command", "manifest-preview", "-GoalPackDir", $fixture),
  @("-Command", "reimport-preview", "-GoalPackDir", $fixture, "-ExistingManifestFile", (Join-Path $fixture "campaign.skybridge.json")),
  @("-Command", "archive-preview", "-GoalPackDir", $fixture),
  @("-Command", "safe-summary", "-GoalPackDir", $fixture)
)
foreach ($args in $commands) {
  $result = Invoke-GoalPackHelper -Arguments $args
  Assert-NoExecutionResult $result
}
$after = Get-GitShortStatusText
if ($before -ne $after) { throw "Git status changed during no-execution smoke." }

$summary = [pscustomobject]@{ ok = $true; commands = $commands.Count; git_status_preserved = $true; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
