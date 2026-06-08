[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | ConvertFrom-Json
foreach ($section in @("## Metadata", "## Context", "## Mission", "## Hard Safety Boundaries", "## Allowed Scope", "## Validation", "## Evidence Requirements", "## Final Campaign State", "## No-Execution Statement")) {
  if ($result.markdown_preview -notmatch [regex]::Escape($section)) { throw "Missing required section: $section" }
}
if (-not $result.validation.required_sections_present) { throw "Validation did not confirm required sections." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-required-sections"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
