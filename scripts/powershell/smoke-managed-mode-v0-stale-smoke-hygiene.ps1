. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$list = Invoke-ManagedModeV0Json "stale-smoke-list"
Assert-ManagedModeV0SafeJson $list
if ($list.no_mutation -ne $true) { throw "Stale smoke hygiene must be non-mutating." }
foreach ($helper in @("scripts/powershell/start-dev-queue-189-200.ps1", "scripts/powershell/skybridge-dev-queue-control.ps1")) {
  if ($list.parameterized_helpers_not_standalone -notcontains $helper) { throw "Missing parameterized helper note for $helper." }
}
Write-ManagedModeV0SmokeResult "managed-mode-v0-stale-smoke-hygiene"
