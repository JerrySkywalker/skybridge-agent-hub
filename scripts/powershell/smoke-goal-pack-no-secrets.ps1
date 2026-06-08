[CmdletBinding()]
param([switch]$Json)

. "$PSScriptRoot\goal-pack-smoke-fixtures.ps1"
$fixture = New-GoalPackSmokeFixture -Name "no-secrets"
$outputs = @()
foreach ($args in @(
  @("-Command", "validate", "-GoalPackDir", $fixture),
  @("-Command", "manifest-preview", "-GoalPackDir", $fixture),
  @("-Command", "reimport-preview", "-GoalPackDir", $fixture, "-ExistingManifestFile", (Join-Path $fixture "campaign.skybridge.json")),
  @("-Command", "archive-preview", "-GoalPackDir", $fixture),
  @("-Command", "safe-summary", "-GoalPackDir", $fixture)
)) {
  $repoRoot = Get-GoalPackSmokeRepoRoot
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-goal-pack.ps1") @args -Json
  if ($LASTEXITCODE -ne 0) { throw "Helper command failed: $raw" }
  Assert-SafeToPaste -Text $raw
  $outputs += $raw
}

$summary = [pscustomobject]@{ ok = $true; checked_outputs = $outputs.Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
