$ErrorActionPreference = "Stop"
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command apply-sandbox -Json | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-upgrade-rollback-sandbox.ps1" -Command upgrade-sandbox -Json | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-upgrade-rollback-sandbox.ps1" -Command rollback-sandbox -Json | Out-Null
$json = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-operator-acceptance.ps1" -Command v2-report -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.schema -ne "skybridge.operator_acceptance_v2_report.v1") { throw "Unexpected operator acceptance v2 schema." }
if ($json.install_sandbox_status -ne "passed" -or $json.extended_fixture_soak_status -ne "passed" -or $json.stability_cleanup_status -ne "passed") { throw "Operator acceptance v2 did not pass required sections." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "operator-acceptance-v2-report"; token_printed = $false } | ConvertTo-Json -Compress
