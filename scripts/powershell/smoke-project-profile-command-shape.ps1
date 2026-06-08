$ErrorActionPreference = "Stop"
$tmpDir = Join-Path ".agent\tmp" "project-profile-smokes"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmp = Join-Path $tmpDir "command-profile.json"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
$profile.validation_commands = @([pscustomobject]@{ id = "bad-shell"; command = "pwsh -Command whoami"; known_fixture = $false })
$profile | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $tmp -Encoding UTF8
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -ProfileFile $tmp -Json | ConvertFrom-Json
if ($result.ok -ne $false) { throw "Arbitrary shell command shape must be rejected." }
if (-not (@($result.errors) -match "arbitrary_shell_command_shape")) { throw "Expected arbitrary_shell_command_shape error." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-command-shape"; token_printed = $false } | ConvertTo-Json -Compress
