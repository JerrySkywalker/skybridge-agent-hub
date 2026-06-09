$text = Get-Content (Join-Path $PSScriptRoot "../../apps/web/src/main.tsx") -Raw
foreach ($required in @("ProposedGoalWorkunitPanel", "Candidate Pipeline", "candidate_execution_disabled", "no task creation", "bounded queue apply disabled")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web candidate panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-proposed-goal-workunit-panel"; token_printed = $false } | ConvertTo-Json -Compress
