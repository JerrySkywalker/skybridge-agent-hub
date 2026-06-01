$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "skybridge-pr-finalize.ps1"
$text = Get-Content -Raw -LiteralPath $scriptPath

if ($text -match 'gh pr view[^\r\n]*--json[^\r\n]*\bmerged\b') {
  throw "skybridge-pr-finalize.ps1 still requests unsupported gh pr view field: merged"
}

if ($text -notmatch 'mergedAt') {
  throw "skybridge-pr-finalize.ps1 should request or handle mergedAt."
}

if ($text -notmatch '\$Pr\.mergedAt') {
  throw "skybridge-pr-finalize.ps1 should derive merged state from Pr.mergedAt when Pr.merged is absent."
}

[pscustomobject]@{
  ok = $true
  scenario = "gh-fields"
  token_printed = $false
} | ConvertTo-Json -Compress
