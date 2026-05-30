param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$config = [pscustomobject]@{ repo_path = (Resolve-Path ".").Path; worker_id = "smoke-worker" }
$missingLeaseTask = [pscustomobject]@{ task_id = "task_missing_lease"; title = "Missing lease guard smoke" }
$missing = Test-SkyBridgeTaskLeaseGuard -Config $config -Task $missingLeaseTask
if ($missing.ok) { throw "Expected missing lease guard to fail." }
if ($missing.reason -ne "claimed_task_missing_active_lease") { throw "Unexpected missing lease reason: $($missing.reason)" }

$activeLeaseTask = [pscustomobject]@{
  task_id = "task_active_lease"
  title = "Active lease guard smoke"
  lease = [pscustomobject]@{
    lease_id = "lease_smoke"
    worker_id = "smoke-worker"
    lease_status = "active"
  }
}
$active = Test-SkyBridgeTaskLeaseGuard -Config $config -Task $activeLeaseTask
if (-not $active.ok) { throw "Expected active lease guard to pass: $($active.reason)" }

[pscustomobject]@{ ok = $true; missing_reason = $missing.reason; active_lease_id = $active.lease_id } | Format-List
