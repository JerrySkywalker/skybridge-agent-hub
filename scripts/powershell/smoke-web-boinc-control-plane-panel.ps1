$text = Get-Content (Join-Path $PSScriptRoot "../../apps/web/src/main.tsx") -Raw
foreach ($required in @("BoincControlPlanePanel", "BOINC Manager", "Control Plane Preview", "Disabled execution actions", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web BOINC control plane panel missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-boinc-control-plane-panel"; token_printed = $false } | ConvertTo-Json -Compress
