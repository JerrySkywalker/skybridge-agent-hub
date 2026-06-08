[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
foreach ($required in @("ProposedGoalReviewPanel", "Review-Only Intake", "fixtureProposedGoalReviewSummary", "Import requires Goal 200", "No import or execute controls", "blocked_draft_count")) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Web proposed-goal review missing: $required" }
}
foreach ($forbidden in @("Import enabled", "Execute enabled", "start-one -Apply", "start-all -Apply")) {
  if ($ui -match [regex]::Escape($forbidden)) { throw "Web contains forbidden control text: $forbidden" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "web-proposed-goal-review"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
