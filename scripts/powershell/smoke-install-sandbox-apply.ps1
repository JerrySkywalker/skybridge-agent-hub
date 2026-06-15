$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command apply-sandbox -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.install_sandbox_manifest.v1") { throw "Unexpected install sandbox manifest schema." }
if ($json.skybridge_ps1_exists -ne $true -or $json.skybridge_cmd_exists -ne $true) { throw "Missing sandbox entrypoints." }
if (@($json.forbidden_paths).Count -ne 0) { throw "Forbidden paths found in sandbox." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "install-sandbox-apply"; token_printed = $false } | ConvertTo-Json -Compress
