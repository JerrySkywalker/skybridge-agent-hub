$ErrorActionPreference = "Stop"
$before = (& git status --short) -join "`n"
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-preview -Json | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-select-preview -Json | Out-Null
$after = (& git status --short) -join "`n"
if ($before -ne $after) { throw "Project profile preview changed git status." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-clean-worktree"; token_printed = $false } | ConvertTo-Json -Compress
