[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-safe-summary -Json | ConvertFrom-Json
foreach ($field in @("proposed_goal_count", "pending_review_count", "blocked_draft_count", "next_action", "import_requires_goal_200", "token_printed")) {
  if (-not $result.PSObject.Properties[$field]) { throw "Safe summary missing field: $field" }
}
if ($result.next_action -ne "review proposed goals in Goal 200") { throw "Unexpected next action." }
if ($result.imported -or $result.executed -or $result.task_created -or $result.worker_loop_started) { throw "Safe summary indicates side effects." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-safe-summary"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
