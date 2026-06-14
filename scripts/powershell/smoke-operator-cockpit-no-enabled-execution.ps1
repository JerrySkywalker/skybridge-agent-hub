$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$web = Get-Content -LiteralPath (Join-Path $root "apps/web/src/main.tsx") -Raw
$desktop = Get-Content -LiteralPath (Join-Path $root "apps/desktop/src/main.tsx") -Raw
foreach ($source in @($web, $desktop)) {
  $match = [regex]::Match($source, "function OperatorCockpitPanel\(\)[\s\S]*?\n}\n")
  if (-not $match.Success) { throw "Missing OperatorCockpitPanel." }
  $text = $match.Value
  foreach ($needle in @("remote_execution_enabled=false", "arbitrary_command_enabled=false", "execution_enabled=false", "queue_apply_enabled=false")) {
    if ($text -notmatch [regex]::Escape($needle)) { throw "Missing disabled capability marker: $needle" }
  }
  if ($text -match "<button(?![^>]*disabled)[^>]*>\s*(Run|Start|Apply|Execute|Claim)\b") { throw "Cockpit exposes an enabled execution button." }
}
[pscustomobject]@{ ok = $true; smoke = "operator-cockpit-no-enabled-execution"; token_printed = $false } | ConvertTo-Json
