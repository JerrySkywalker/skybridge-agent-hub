$ErrorActionPreference = "Stop"
$ui = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @("ProjectProfileReviewPanel", "Project Profile Review", "Selected project", "Profile hash", "Default branch", "Allowed paths", "Blocked paths", "Validation commands", "Project selection apply disabled", "External repo mutation disabled")) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Desktop project profile review surface missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-project-profile-review"; token_printed = $false } | ConvertTo-Json -Compress
