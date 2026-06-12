. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-ac-ok"
if ($gate.admin_required -ne $false) { throw "Resource gate must not require admin." }
Write-LocalResourceSmokeResult "local-resource-enforcement-no-admin-required"
