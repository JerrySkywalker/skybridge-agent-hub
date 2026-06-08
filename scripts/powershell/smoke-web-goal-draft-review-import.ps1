[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
foreach ($required in @("Controlled Review / Import", "Approve preview", "Reject preview", "Edit staged", "Import preview", "Import apply disabled", "reason-gated", "manifest diff", "execution review required")) {
  if ($ui -notmatch [regex]::Escape($required) -and $client -notmatch [regex]::Escape($required)) { throw "Web review/import surface missing: $required" }
}
foreach ($forbidden in @("Start imported goal", "Execute imported goal", "start-all -Apply", "resume -Apply")) {
  if ($ui -match [regex]::Escape($forbidden)) { throw "Web contains forbidden execution control: $forbidden" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "web-goal-draft-review-import"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
