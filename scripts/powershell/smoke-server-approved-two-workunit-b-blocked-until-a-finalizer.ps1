$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$script = Join-Path $root "scripts\powershell\skybridge-server-approved-two-workunit-trial.ps1"
$gate = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command workunit-b-apply-gate -AuthorizeTrial226 -Json | Out-String).Trim() | ConvertFrom-Json
if ($gate.can_apply_workunit_b -ne $false -or $gate.workunit_a_finalized -ne $false) { throw "Workunit B was not blocked before A finalizer." }
[pscustomobject]@{ ok = $true; scenario = "workunit-b-blocked-until-a-finalizer"; token_printed = $false } | ConvertTo-Json -Compress
