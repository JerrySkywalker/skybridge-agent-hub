$text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @("LocalResourceEnforcementPanel", "Resource Gate", "Can run one-at-a-time", "No power mutation", "Admin required", "No task execution", "token_printed")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Desktop local resource enforcement panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-local-resource-enforcement-panel"; token_printed = $false } | ConvertTo-Json -Compress
