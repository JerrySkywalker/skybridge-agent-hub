$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$scriptPath = Join-Path $repoRoot "scripts\powershell\start-dev-queue-189-200.ps1"
$campaignScriptPath = Join-Path $repoRoot "scripts\powershell\skybridge-campaign.ps1"

$startScript = Get-Content -Raw -LiteralPath $scriptPath
$campaignScript = Get-Content -Raw -LiteralPath $campaignScriptPath

if ($startScript -notmatch 'if \(\$Apply\) \{ \$runArgs \+= "-Apply" \}') {
  throw "start-dev-queue-189-200.ps1 must forward -Apply to the campaign runner."
}
if ($startScript -notmatch 'run-until-hold') {
  throw "start-dev-queue-189-200.ps1 must invoke the campaign runner."
}
if ($campaignScript -notmatch '\$runnerOwnsLock = \(\$lock -and \[string\]\$lock\.lock_owner -eq \[string\]\$state\.runner_id\)') {
  throw "skybridge-campaign.ps1 must compare lock_owner with the current runner_id."
}
if ($campaignScript -notmatch 'active"\s+-and\s+-not\s+\$runnerOwnsLock') {
  throw "Self-owned active locks must not produce active_runner_lock."
}
if ($campaignScript -notmatch 'Release-CampaignRunnerLock -Lock \$lock -Reason \$state\.runner_status') {
  throw "Self-owned apply locks must still be released."
}

[pscustomobject]@{
  ok = $true
  scenario = "start-dev-queue-apply-self-lock-regression"
  apply_forwarded = $true
  self_lock_owner_check = $true
  token_printed = $false
} | ConvertTo-Json -Compress
