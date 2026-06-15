$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-upgrade-rollback-sandbox.ps1" -Command migration-preview -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.sandbox_migration_report.v1" -or $json.status -ne "preview") { throw "Unexpected migration preview." }
if ($json.channel -ne "local" -or $json.network_update -ne $false -or $json.github_release -ne $false -or $json.binary_download -ne $false) { throw "Migration preview crossed safety boundary." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "version-channel-migration-preview"; token_printed = $false } | ConvertTo-Json -Compress
