$text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("ManagedModeV0StatusPanel", "Managed Mode v0", "Release Status", "resource gate required", "No next execution authorized", "General bounded queue apply", "Execution disabled banner")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web Managed Mode v0 panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-managed-mode-v0-status-panel"; token_printed = $false } | ConvertTo-Json -Compress
