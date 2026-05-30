param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-lock.ps1")

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-dirty-tree-guard-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
  git -C $tempDir init -b main | Out-Null
  git -C $tempDir config user.email "skybridge-smoke@example.invalid" | Out-Null
  git -C $tempDir config user.name "SkyBridge Smoke" | Out-Null
  Set-Content -LiteralPath (Join-Path $tempDir "README.md") -Value "# Smoke" -Encoding UTF8
  git -C $tempDir add README.md | Out-Null
  git -C $tempDir commit -m "Initialize smoke repo" | Out-Null
  Set-Content -LiteralPath (Join-Path $tempDir "dirty.md") -Value "dirty" -Encoding UTF8

  $config = [pscustomobject]@{ repo_path = $tempDir; worker_id = "smoke-worker" }
  $task = [pscustomobject]@{ task_id = "task_dirty_guard"; title = "Dirty guard smoke" }
  $result = Test-SkyBridgeDirtyTreeGuard -Config $config -Task $task
  if ($result.ok) { throw "Expected dirty tree guard to fail." }
  if (@($result.changed_files).Count -eq 0) { throw "Expected dirty tree guard to report changed files." }

  [pscustomobject]@{ ok = $true; guard = $result.guard; changed_files = @($result.changed_files) } | Format-List
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
