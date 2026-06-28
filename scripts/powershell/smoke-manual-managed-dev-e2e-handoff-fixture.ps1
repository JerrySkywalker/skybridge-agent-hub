. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-e2e-handoff.ps1" @(
  "-Command", "status"
)

$expectedMilestones = @("M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8")
$seen = @($result.capability_matrix | ForEach-Object { [string]$_.milestone })
foreach ($milestone in $expectedMilestones) {
  if ($seen -notcontains $milestone) { throw "Missing milestone $milestone." }
}

foreach ($entry in @($result.capability_matrix)) {
  $path = [string]$entry.manual_script
  if ([string]::IsNullOrWhiteSpace($path)) { throw "Manual script path missing." }
  Assert-FileExists $path
}

Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-managed-dev-e2e-handoff-fixture"
