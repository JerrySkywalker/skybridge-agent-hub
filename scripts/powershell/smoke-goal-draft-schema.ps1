[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | ConvertFrom-Json
$metadata = $result.draft
foreach ($field in @("proposed_goal_id", "title", "source", "proposed_markdown_path", "content_hash", "safety_classification", "review_status", "suggested_order", "suggested_dependencies", "allowed_task_types", "blocked_task_types", "expected_outputs", "review_notes", "generated_at", "token_printed")) {
  if (-not $metadata.PSObject.Properties[$field]) { throw "Missing proposed goal schema field: $field" }
}
if ($metadata.token_printed -ne $false) { throw "token_printed must be false." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-schema"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
