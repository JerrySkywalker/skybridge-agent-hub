[CmdletBinding()]
param([switch]$Json)
$web = Get-Content (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx") -Raw
foreach ($required in @("Bounded Queue Preview", "apply disabled", "no task creation", "no task claim", "no execution", "no PR creation", "bounded queue apply disabled")) {
  if ($web -notmatch [regex]::Escape($required)) { throw "Web bounded queue preview panel missing $required." }
}
[pscustomobject]@{ ok = $true; scenario = "web-bounded-queue-preview-panel"; token_printed = $false } | ConvertTo-Json -Compress
