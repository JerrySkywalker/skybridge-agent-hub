$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command tag-preview -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.self_bootstrap_tag_plan.v1") { throw "Unexpected tag plan schema." }
if ($result.stop_required -eq $true) { throw "Release tag exists on a different commit." }
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-tag-preview"; token_printed = $false } | ConvertTo-Json
