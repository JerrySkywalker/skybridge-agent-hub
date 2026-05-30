param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$config = [pscustomobject]@{ repo_path = (Resolve-Path ".").Path; worker_id = "smoke-worker" }
$task = [pscustomobject]@{
  task_id = "task_active_pr_guard"
  title = "Active PR guard smoke"
  result = [pscustomobject]@{ pr_url = "https://github.example.invalid/org/repo/pull/123" }
}
$result = Test-SkyBridgeActivePrGuard -Config $config -Task $task
if ($result.ok) { throw "Expected active PR guard to block a task with an existing PR URL." }
if ($result.reason -ne "task_already_has_child_pr") { throw "Unexpected active PR guard reason: $($result.reason)" }

[pscustomobject]@{ ok = $true; guard = $result.guard; reason = $result.reason } | Format-List
