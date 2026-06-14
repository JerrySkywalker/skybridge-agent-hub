$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command release-preview -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.self_bootstrap_release_report.v1") { throw "Unexpected release report schema." }
if ($result.bootstrap_complete -ne $true) { throw "Release report does not mark bootstrap complete." }
if ($result.ready_for_goal_230 -ne $true) { throw "Release report is not ready for goal 230." }
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-release-report"; token_printed = $false } | ConvertTo-Json
