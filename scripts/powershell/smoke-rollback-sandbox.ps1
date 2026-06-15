$ErrorActionPreference = "Stop"
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command apply-sandbox -Json | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-upgrade-rollback-sandbox.ps1" -Command upgrade-sandbox -Json | Out-Null
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-upgrade-rollback-sandbox.ps1" -Command rollback-sandbox -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.status -ne "rolled_back" -or $json.writes_only_under_install_sandbox -ne $true) { throw "Rollback sandbox failed." }
if ($json.host_mutation_allowed -ne $false -or $json.token_printed -ne $false) { throw "Rollback sandbox safety contract failed." }
[pscustomobject]@{ ok = $true; scenario = "rollback-sandbox"; token_printed = $false } | ConvertTo-Json -Compress
