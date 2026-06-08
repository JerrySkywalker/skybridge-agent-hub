$ErrorActionPreference = "Stop"
$ui = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\web\src\main.tsx")
foreach ($required in @("ProjectProfileReviewPanel", "Project Profile Review", "Selected project", "Profile hash", "Repo identity", "Default branch", "Allowed paths", "Blocked paths", "Validation commands", "No execution controls")) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Web project profile review surface missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "web-project-profile-review"; token_printed = $false } | ConvertTo-Json -Compress
