$text = Get-Content (Join-Path $PSScriptRoot "../../packages/client/src/index.ts") -Raw
foreach ($required in @("workunit_candidate_pack", "candidate_preview_count", "fixtureWorkunitCandidatePack", "bounded_queue_preview_only")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Bounded queue preview missing candidate field $required" }
}
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-preview-includes-candidates"; token_printed = $false } | ConvertTo-Json -Compress
