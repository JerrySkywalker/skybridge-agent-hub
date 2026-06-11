$text = Get-Content (Join-Path $PSScriptRoot "../../apps/web/src/main.tsx") -Raw
foreach ($required in @("ManagedModeRunRegistryPanel", "Repeatable Managed Mode", "completed runs", "Next run preview", "Open hold status", "Apply disabled reason", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web managed-mode run registry panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-managed-mode-run-registry-panel"; token_printed = $false } | ConvertTo-Json -Compress
