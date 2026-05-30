param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-stale-lock-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
  $config = [pscustomobject]@{ repo_path = $tempDir; worker_id = "smoke-worker" }
  $task = [pscustomobject]@{ task_id = "task_stale_lock"; title = "Stale lock smoke" }
  $lockPath = Get-SkyBridgeRepoLockPath -Config $config
  New-Item -ItemType Directory -Path (Split-Path -Parent $lockPath) -Force | Out-Null
  [pscustomobject]@{
    task_id = "old_task"
    worker_id = "old-worker"
    pid = 999999
    created_at = ([datetime]::UtcNow.AddDays(-2)).ToString("o")
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lockPath -Encoding UTF8

  $lock = New-SkyBridgeRepoLock -Config $config -Task $task -MaxStaleMinutes 1
  if (-not $lock.ok) { throw "Expected stale lock recovery to acquire a new lock." }
  if (-not $lock.stale_recovered) { throw "Expected stale_recovered=true." }
  if (-not (Get-ChildItem -LiteralPath (Split-Path -Parent $lockPath) -Filter "*.stale.*.json")) { throw "Expected stale lock archive." }
  Remove-SkyBridgeRepoLock -Lock $lock | Out-Null

  [pscustomobject]@{ ok = $true; stale_recovered = [bool]$lock.stale_recovered } | Format-List
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
