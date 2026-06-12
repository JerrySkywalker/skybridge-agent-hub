. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$list = Invoke-ManagedModeV0Json "stale-smoke-list"
if ($list.no_mutation -ne $true) { throw "Stale smoke list must be no-mutation." }
if (@($list.parameterized_helpers_not_standalone).Count -lt 1) { throw "Expected parameterized helper guidance." }
Assert-ManagedModeV0SafeJson $list
Write-ManagedModeV0SmokeResult "managed-mode-v0-stale-smoke-list"
