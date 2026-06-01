[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$goalPackDir = Resolve-Path (Join-Path $PSScriptRoot "..\..\goals\dev-queue-189-200")
$files = @(Get-ChildItem -LiteralPath $goalPackDir -Filter "super-*.md" -File | Sort-Object Name)
if ($files.Count -ne 12) { throw "Expected 12 dev queue goal files; found $($files.Count)." }

$requiredSections = @(
  "## Context",
  "## Mission",
  "## Global Safety Boundaries",
  "## Phase A: Preflight",
  "## Validation Phase",
  "## Final Status Phase",
  "## PR Package Phase",
  "## Success Criteria",
  "## Stop And Hold Conditions",
  "## Evidence Requirements",
  "## Non-goals"
)
$expectedRequires = @{}
$previous = $null
foreach ($file in $files) {
  $raw = Get-Content -Raw -LiteralPath $file.FullName
  $match = [regex]::Match($raw, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { throw "$($file.Name) is missing fenced JSON metadata." }
  $meta = $match.Groups[1].Value | ConvertFrom-Json
  $expectedRequires[[string]$meta.goal_id] = @($meta.requires)
  foreach ($section in $requiredSections) {
    if ($raw -notlike "*$section*") { throw "$($file.Name) is missing section $section." }
  }
  foreach ($phrase in @("Do not print tokens", "Do not mutate GitHub repository settings", "Do not modify production", "no secret printing")) {
    if ($raw -notlike "*$phrase*") { throw "$($file.Name) is missing safety phrase: $phrase" }
  }
  if ($raw -match "(?i)(sk-[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |OPENSSH |PRIVATE )?PRIVATE KEY-----)") { throw "$($file.Name) contains secret-looking text." }
  if ($previous -and @($meta.requires) -notcontains $previous) { throw "$($file.Name) does not require previous goal $previous." }
  if (-not $previous -and @($meta.requires).Count -ne 0) { throw "$($file.Name) should not require an earlier in-pack goal." }
  $previous = [string]$meta.goal_id
}

$summary = [pscustomobject]@{ ok = $true; files = $files.Count; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
