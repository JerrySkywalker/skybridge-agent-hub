[CmdletBinding()]
param([switch]$Json)
$desktop = Get-Content (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx") -Raw
foreach ($required in @("Workunit / Bounded Queue Preview", "Bounded Queue Apply disabled", "No task creation", "No task claim", "No execution", "start_bounded_queue_apply_available")) {
  if ($desktop -notmatch [regex]::Escape($required)) { throw "Desktop workunit preview panel missing $required." }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-workunit-preview-panel"; token_printed = $false } | ConvertTo-Json -Compress
