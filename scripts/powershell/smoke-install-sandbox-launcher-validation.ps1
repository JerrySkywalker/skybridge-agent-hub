$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command verify -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.install_sandbox_verification.v1" -or $json.ok -ne $true) { throw "Sandbox launcher validation failed." }
if ($json.starts_codex_worker -ne $false -or $json.runs_workunit_apply -ne $false -or $json.claims_task -ne $false -or $json.runs_queue_apply -ne $false) { throw "Forbidden sandbox command capability detected." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "install-sandbox-launcher-validation"; token_printed = $false } | ConvertTo-Json -Compress
