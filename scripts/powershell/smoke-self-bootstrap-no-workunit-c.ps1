$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$trialDir = Join-Path $root ".agent/tmp/server-approved-two-workunit-trial-226"
$matches = @(Get-ChildItem -LiteralPath $trialDir -Recurse -File | Where-Object { $_.Name -match "workunit-c|workunit_c" })
if ($matches.Count -ne 0) { throw "Unexpected Workunit C evidence exists." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-no-workunit-c"; token_printed = $false } | ConvertTo-Json
