$text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @("ManagedModeV0StatusPanel", "Managed Mode v0", "Completed runs", "No next execution authorized", "Resource gate required", "General bounded queue apply", "Execution disabled")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Desktop Managed Mode v0 panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-managed-mode-v0-status-panel"; token_printed = $false } | ConvertTo-Json -Compress
