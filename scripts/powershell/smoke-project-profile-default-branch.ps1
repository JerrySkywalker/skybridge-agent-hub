$ErrorActionPreference = "Stop"
$tmpDir = Join-Path ".agent\tmp" "project-profile-smokes"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmp = Join-Path $tmpDir "branch-profile.json"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
$profile.default_branch = "develop"
$profile | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $tmp -Encoding UTF8
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -ProfileFile $tmp -ExpectedDefaultBranch main -Json | ConvertFrom-Json
if ($result.ok -ne $true) { throw "Default branch mismatch should warn, not invalidate the otherwise safe fixture." }
if (-not (@($result.warnings) -contains "project_default_branch_mismatch")) { throw "Expected project_default_branch_mismatch warning." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-default-branch"; token_printed = $false } | ConvertTo-Json -Compress
