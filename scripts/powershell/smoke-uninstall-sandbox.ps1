$ErrorActionPreference = "Stop"
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command apply-sandbox -Json | Out-Null
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-uninstall-sandbox.ps1" -Command uninstall-sandbox -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.status -ne "clean" -or $json.current_exists -ne $false) { throw "Uninstall sandbox did not clean current sandbox." }
if ($json.deletes_outside_install_sandbox -ne $false -or $json.host_mutation_allowed -ne $false) { throw "Uninstall sandbox safety contract failed." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "uninstall-sandbox"; token_printed = $false } | ConvertTo-Json -Compress
