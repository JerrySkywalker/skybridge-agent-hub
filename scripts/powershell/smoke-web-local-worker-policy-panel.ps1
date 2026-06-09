$ErrorActionPreference = "Stop"
$web = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("WebLocalWorkerPolicyPanel", "Resident Policy", "preview only", "Web policy summary is read-only", "token_printed=false")) {
  if ($web -notmatch [regex]::Escape($required)) { throw "Web local worker policy panel missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-local-worker-policy-panel"; token_printed = $false } | ConvertTo-Json -Compress
