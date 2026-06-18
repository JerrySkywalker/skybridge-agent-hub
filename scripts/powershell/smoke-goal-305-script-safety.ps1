[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$relativePaths = @(
  "scripts/powershell/skybridge-verify-cloud-autodeploy.ps1",
  "scripts/powershell/skybridge-create-rc-tag.ps1",
  "scripts/powershell/skybridge-current-pr-status.ps1"
)

foreach ($relative in $relativePaths) {
  $path = Join-Path $RepoRoot $relative
  Assert-FileExists $relative
  $text = Get-Content -Raw -LiteralPath $path
  Assert-NoUnsafeText $text
  foreach ($forbidden in @("displayTitle", "display_title", "gh run rerun", "workflow run deploy-cloud", "gh workflow run", "gh release create", "docker system prune")) {
    if ($text -match [regex]::Escape($forbidden)) { throw "Forbidden pattern '$forbidden' found in $relative." }
  }
}

$summary = [pscustomobject]@{
  ok = $true
  checked_scripts = $relativePaths
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "goal-305-script-safety" }
