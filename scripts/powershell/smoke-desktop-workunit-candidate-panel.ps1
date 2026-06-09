$text = Get-Content (Join-Path $PSScriptRoot "../../apps/desktop/src/main.tsx") -Raw
foreach ($required in @("WorkunitCandidateReviewPanel", "Workunit Candidate Review", "Candidate execution disabled", "Bounded queue apply disabled", "token_printed")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Desktop candidate panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-workunit-candidate-panel"; token_printed = $false } | ConvertTo-Json -Compress
