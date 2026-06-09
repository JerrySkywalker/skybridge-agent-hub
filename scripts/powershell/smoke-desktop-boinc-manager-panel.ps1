$text = Get-Content (Join-Path $PSScriptRoot "../../apps/desktop/src/main.tsx") -Raw
foreach ($required in @("BoincManagerPanel", "BOINC Manager Control Plane", "bounded_queue_readiness", "action_matrix.disabled", "token_printed")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Desktop BOINC manager panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-boinc-manager-panel"; token_printed = $false } | ConvertTo-Json -Compress
