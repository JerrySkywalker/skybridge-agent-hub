$ErrorActionPreference = "Stop"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
foreach ($field in @("project_id", "display_name", "repo_path", "repo_identity", "default_branch", "allowed_paths", "blocked_paths", "validation_commands", "worker_profile", "goal_pack", "ci_policy", "project_policy", "profile_hash", "token_printed")) {
  if (-not $profile.PSObject.Properties[$field]) { throw "Missing project profile field: $field" }
}
if ($profile.token_printed -ne $false) { throw "token_printed must be false." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-schema"; token_printed = $false } | ConvertTo-Json -Compress
