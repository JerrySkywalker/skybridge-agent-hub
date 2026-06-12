. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$registry = Invoke-ManagedModeRunJson "registry"
$record = @($registry.records | Where-Object { $_.run_id -eq "managed-mode-run-209" }) | Select-Object -First 1
if (-not $record) { throw "Expected managed-mode-run-209 registry record." }
if ($record.state -ne "completed") { throw "Expected managed-mode-run-209 completed state." }
if ($registry.completed_runs.run_id -notcontains "managed-mode-run-209") { throw "Expected run 209 in completed_runs." }
Assert-ManagedModeRunSafeJson $registry
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-completed-state"
