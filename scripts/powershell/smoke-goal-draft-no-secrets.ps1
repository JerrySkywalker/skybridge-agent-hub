[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-goal-draft.ps1" -Command goal-draft-generate-preview -Json | ConvertFrom-Json
$text = $result.markdown_preview
$patterns = @("sk-[A-Za-z0-9_-]{20,}", "gh[pousr]_[A-Za-z0-9_]{20,}", "authorization\s*[:=]\s*bearer", "-----BEGIN [A-Z ]*PRIVATE KEY-----")
foreach ($pattern in $patterns) {
  if ($text -match $pattern) { throw "Secret-looking content detected." }
}
if ($result.token_printed -ne $false) { throw "token_printed must be false." }
$summary = [pscustomobject]@{ ok = $true; scenario = "goal-draft-no-secrets"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
