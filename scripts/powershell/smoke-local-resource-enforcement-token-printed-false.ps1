. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
foreach ($command in @("status", "preview", "safe-summary", "enforcement-gate", "run-allowance", "fixture-ac-ok", "fixture-battery-blocked", "fixture-memory-blocked", "fixture-idle-required", "fixture-network-blocked")) {
  $result = Invoke-LocalResourceJson $command
  Assert-LocalResourceSafeJson $result
}
Write-LocalResourceSmokeResult "local-resource-enforcement-token-printed-false"
