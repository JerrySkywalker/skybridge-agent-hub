$ErrorActionPreference = "Stop"
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-local-soak.ps1" -Command stability-cleanup -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.stability_cleanup_report.v1" -or $json.status -ne "passed") { throw "Stability cleanup report failed." }
if ($json.stale_sandbox_cleanup_preview.deletes_outside_install_sandbox -ne $false -or $json.orphan_fixture_process_detection.kills_arbitrary_processes -ne $false) { throw "Stability cleanup safety contract failed." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "stability-cleanup-report"; token_printed = $false } | ConvertTo-Json -Compress
