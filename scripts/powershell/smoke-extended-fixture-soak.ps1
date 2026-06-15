$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-local-soak.ps1" -Command extended-fixture-soak -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.extended_fixture_soak.v1" -or $json.status -ne "passed") { throw "Extended fixture soak failed." }
if ($json.iterations_completed -gt 5 -or $json.max_duration_seconds -gt 180) { throw "Extended fixture soak bounds failed." }
if ($json.background_process_left_running -ne $false -or $json.raw_logs_persisted -ne $false -or $json.token_printed -ne $false) { throw "Extended fixture soak safety contract failed." }
[pscustomobject]@{ ok = $true; scenario = "extended-fixture-soak"; token_printed = $false } | ConvertTo-Json -Compress
