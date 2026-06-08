[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
foreach ($required in @("ProposedGoalReviewPanel", "Proposed Goal Review", "fixtureProposedGoalReviewSummary", "Import disabled", "Execute disabled", "Import requires Goal 200", "content_hash")) {
  if ($ui -notmatch [regex]::Escape($required) -and $client -notmatch [regex]::Escape($required)) { throw "Desktop proposed-goal review missing: $required" }
}
foreach ($forbidden in @("Import enabled", "Execute enabled")) {
  if ($ui -match [regex]::Escape($forbidden)) { throw "Desktop contains forbidden control text: $forbidden" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "desktop-proposed-goal-review"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
