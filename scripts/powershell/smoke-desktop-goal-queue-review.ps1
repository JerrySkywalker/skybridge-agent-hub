[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

foreach ($required in @(
  "Manual Goal Queue Review",
  "fixtureGoalQueueReviewSummary",
  "Hash drift count",
  "Re-import preview",
  "Archive preview",
  "No execution controls",
  "Queue execution enabled"
)) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Desktop review surface missing: $required" }
}
foreach ($required in @("GoalQueueReviewSummary", "fixtureGoalQueueReviewSummary", "queue_execution_enabled: false", "worker_loop_started: false")) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Client review fixture missing: $required" }
}

$summary = [pscustomobject]@{ ok = $true; scenario = "desktop-goal-queue-review"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
