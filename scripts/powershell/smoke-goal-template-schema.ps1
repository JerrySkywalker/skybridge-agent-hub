[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$templateDir = Join-Path $repoRoot "goals\templates"
$required = @(
  "super-goal.md",
  "patch-goal.md",
  "recovery-goal.md",
  "dashboard-control-goal.md",
  "worker-service-goal.md",
  "generated-proposed-goal.md"
)

foreach ($file in $required) {
  $path = Join-Path $templateDir $file
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing template: $file" }
  $text = Get-Content -Raw -LiteralPath $path
  $match = [regex]::Match($text, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { throw "Template missing metadata: $file" }
  $meta = $match.Groups[1].Value | ConvertFrom-Json
  if ($meta.schema -ne "skybridge.super_goal.v1") { throw "Invalid template schema: $file" }
  foreach ($section in @("Context", "Mission", "Hard Safety Boundaries", "Allowed Scope", "Validation", "Evidence Requirements", "Final Campaign State", "No Execution Statement")) {
    if ($text -notmatch "(?im)^##\s+$([regex]::Escape($section))\s*$") { throw "$file missing $section" }
  }
  if ($text -notmatch "token_printed=false") { throw "$file missing token_printed=false" }
}

$summary = [pscustomobject]@{ ok = $true; template_count = $required.Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
