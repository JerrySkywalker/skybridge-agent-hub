$ErrorActionPreference = "Stop"

$output = Join-Path ".agent\tmp\campaign-reports" "smoke-campaign-report.md"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" runner-report -CampaignId dev-queue-189-200 -ApiBase https://skybridge.example.com -OutputFile $output -Json | ConvertFrom-Json
if (-not $result.ok) { throw "Expected runner-report ok." }
if ($result.token_printed -ne $false -or $result.report.token_printed -ne $false) { throw "Expected token_printed=false." }
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw "Expected Markdown output file." }
$markdown = Get-Content -Raw -LiteralPath $output

$headings = @(
  "# Campaign Runner Report",
  "## Campaign Summary",
  "## Current Step",
  "## Previous Step",
  "## Step Ledger",
  "## Evidence Ledger",
  "## PR/CI Summary",
  "## Finalizer Summary",
  "## Recovery Summary",
  "## Hygiene Summary",
  "## Queue Control Readiness",
  "## Blockers And Warnings",
  "## Acceptance Summary"
)
foreach ($heading in $headings) {
  if ($markdown -notmatch [regex]::Escape($heading)) { throw "Markdown missing heading: $heading" }
}
if ($markdown -notmatch "Token printed: false") { throw "Markdown missing token_printed=false equivalent." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-markdown"; output = $output; token_printed = $false } | ConvertTo-Json -Compress
