$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command plan -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.install_sandbox_plan.v1") { throw "Unexpected install sandbox plan schema." }
if ($json.writes_only_under_install_sandbox -ne $true -or $json.host_install -ne $false) { throw "Install sandbox plan containment failed." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "install-sandbox-plan"; token_printed = $false } | ConvertTo-Json -Compress
