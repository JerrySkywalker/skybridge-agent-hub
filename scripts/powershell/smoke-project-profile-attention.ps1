$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
foreach ($required in @("project_profile_invalid", "project_profile_missing", "project_repo_path_invalid", "project_default_branch_mismatch", "project_policy_blocked_path", "project_selection_preview_only")) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Missing project attention type: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "project-profile-attention"; token_printed = $false } | ConvertTo-Json -Compress
