[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
foreach ($required in @("proposed_goal_created", "proposed_goal_needs_review", "proposed_goal_blocked", "proposed_goal_rejected", "unsafe_goal_draft_detected", "import_requires_goal_200")) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Client attention model missing: $required" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-attention"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
