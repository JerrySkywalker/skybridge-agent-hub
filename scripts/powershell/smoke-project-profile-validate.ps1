$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -Json | ConvertFrom-Json
if ($result.ok -ne $true -or $result.validation_status -ne "valid") { throw "Expected valid default project profile." }
if ($result.validation_commands | Where-Object { $_.executes -ne $false }) { throw "Validation command execution flag must stay false." }
if ($result.token_printed -ne $false) { throw "token_printed must be false." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-validate"; profile_hash = $result.profile_hash; token_printed = $false } | ConvertTo-Json -Compress
