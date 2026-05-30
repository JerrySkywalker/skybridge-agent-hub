param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-repo-lock-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
  $config = [pscustomobject]@{ repo_path = $tempDir; worker_id = "smoke-worker" }
  $task = [pscustomobject]@{ task_id = "task_repo_lock"; title = "Repo lock smoke" }
  $lock = New-SkyBridgeRepoLock -Config $config -Task $task
  if (-not $lock.ok) { throw "Expected repo lock acquisition to succeed: $($lock.error)" }
  if (-not (Test-Path -LiteralPath $lock.lock_path -PathType Leaf)) { throw "Expected repo lock file to exist." }
  $stored = Read-SkyBridgeRepoLock -Path $lock.lock_path
  if ($stored.task_id -ne $task.task_id) { throw "Expected lock task_id to be persisted." }
  if (-not (Remove-SkyBridgeRepoLock -Lock $lock)) { throw "Expected repo lock cleanup to succeed." }
  if (Test-Path -LiteralPath $lock.lock_path -PathType Leaf) { throw "Expected repo lock file to be removed." }

  [pscustomobject]@{ ok = $true; lock_path = $lock.lock_path; task_id = $lock.task_id } | Format-List
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
