$text = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("WebLocalResourceEnforcementPanel", "Resource Gate", "Run Allowance", "enforcement gate", "no task claim", "no task execution", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Web local resource enforcement summary missing $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-local-resource-enforcement-summary"; token_printed = $false } | ConvertTo-Json -Compress
