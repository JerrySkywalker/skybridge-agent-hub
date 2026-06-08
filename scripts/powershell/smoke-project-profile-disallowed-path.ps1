$ErrorActionPreference = "Stop"
$tmpDir = Join-Path ".agent\tmp" "project-profile-smokes"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmp = Join-Path $tmpDir "disallowed-path-profile.json"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
$profile.allowed_paths = @("..")
$profile | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $tmp -Encoding UTF8
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -ProfileFile $tmp -Json | ConvertFrom-Json
if ($result.ok -ne $false) { throw "Out-of-repo allowed path must be rejected." }
if (-not (@($result.errors) -match "allowed_path_outside_repo")) { throw "Expected allowed_path_outside_repo error." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-disallowed-path"; token_printed = $false } | ConvertTo-Json -Compress
