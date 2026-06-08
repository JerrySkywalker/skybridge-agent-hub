$ErrorActionPreference = "Stop"
$one = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-hash -Json | ConvertFrom-Json
$two = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-hash -Json | ConvertFrom-Json
if ($one.profile_hash -ne $two.profile_hash) { throw "Profile hash must be stable." }
if ($one.profile_hash -notmatch '^[a-f0-9]{64}$') { throw "Profile hash must be a SHA-256 hex string." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-hash"; profile_hash = $one.profile_hash; token_printed = $false } | ConvertTo-Json -Compress
