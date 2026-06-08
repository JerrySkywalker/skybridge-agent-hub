[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")

foreach ($required in @(
  "GoalQueueReviewPanel",
  "Manual Queue Authoring",
  "Current pack hash",
  "Hash drift",
  "Dependency/order",
  "Re-import preview",
  "Archive preview",
  "No execution controls are available"
)) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Web review surface missing: $required" }
}
foreach ($forbidden in @("start-one -Apply", "start-all -Apply", "resume -Apply")) {
  if ($ui -match [regex]::Escape($forbidden)) { throw "Web review surface contains forbidden command: $forbidden" }
}

$summary = [pscustomobject]@{ ok = $true; scenario = "web-goal-queue-review"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
