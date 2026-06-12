$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$text = (Get-Content -Raw -LiteralPath (Join-Path $root "apps\web\src\main.tsx")) + "`n" + (Get-Content -Raw -LiteralPath (Join-Path $root "packages\client\src\index.ts"))
foreach ($required in @("ManagedModeV0StatusPanel", "Managed Mode v0", "managed_mode_v0_9_readiness", "managed-mode-run-211", "No next execution authorized", "resource gate required", "General bounded queue apply")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web Managed Mode v0.9 panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-managed-mode-v0-9-panel"; token_printed = $false } | ConvertTo-Json -Compress
