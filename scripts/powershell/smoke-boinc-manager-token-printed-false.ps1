. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
foreach ($command in @("status", "safe-summary", "action-matrix", "mode-preview", "operator-guidance", "fixture-state")) {
  $null = Invoke-BoincManagerJson $command
}
Write-SmokeResult "boinc-manager-token-printed-false"
