$ErrorActionPreference = "Stop"
$tmpDir = Join-Path ".agent\tmp" "project-profile-smokes"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmp = Join-Path $tmpDir "goal-pack-profile.json"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
$profile.goal_pack.default_goal_pack_dir = "../outside-goals"
$profile.goal_pack.allowed_goal_pack_dirs = @("../outside-goals")
$profile | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $tmp -Encoding UTF8
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -ProfileFile $tmp -Json | ConvertFrom-Json
if ($result.ok -ne $false) { throw "Invalid goal pack path must be rejected." }
if (-not (@($result.errors) -match "goal_pack_path_outside_repo|invalid_goal_pack_path")) { throw "Expected goal pack path error." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-goal-pack"; token_printed = $false } | ConvertTo-Json -Compress
