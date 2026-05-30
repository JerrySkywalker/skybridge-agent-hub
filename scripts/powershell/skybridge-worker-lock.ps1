function Get-SkyBridgeRepoPath {
  param($Config)
  if (-not $Config -or [string]::IsNullOrWhiteSpace([string]$Config.repo_path)) {
    throw "Worker config is missing repo_path."
  }
  return (Resolve-Path -LiteralPath ([string]$Config.repo_path) -ErrorAction Stop).Path
}

function Get-SkyBridgeRepoLockPath {
  param($Config)
  $repoPath = Get-SkyBridgeRepoPath -Config $Config
  return (Join-Path $repoPath ".agent/locks/skybridge-edge-worker.lock.json")
}

function Test-SkyBridgeProcessAlive {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return $false }
  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Read-SkyBridgeRepoLock {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
  } catch {
    return [pscustomobject]@{ malformed = $true; path = $Path }
  }
}

function Test-SkyBridgeRepoLockStale {
  param($Lock, [int]$MaxStaleMinutes = 240)
  if (-not $Lock) { return $false }
  if ($Lock.malformed) { return $true }
  $createdAt = $null
  try { $createdAt = [datetimeoffset]::Parse([string]$Lock.created_at).UtcDateTime } catch {}
  $ageStale = $createdAt -and (([datetime]::UtcNow - $createdAt).TotalMinutes -gt $MaxStaleMinutes)
  $pidAlive = Test-SkyBridgeProcessAlive -ProcessId ([int]$Lock.pid)
  return (-not $pidAlive) -or $ageStale
}

function New-SkyBridgeRepoLock {
  param($Config, $Task, [int]$MaxStaleMinutes = 240)
  $path = Get-SkyBridgeRepoLockPath -Config $Config
  $dir = Split-Path -Parent $path
  New-Item -ItemType Directory -Path $dir -Force | Out-Null

  $existing = Read-SkyBridgeRepoLock -Path $path
  $staleRecovered = $false
  if ($existing) {
    if (-not (Test-SkyBridgeRepoLockStale -Lock $existing -MaxStaleMinutes $MaxStaleMinutes)) {
      return [pscustomobject]@{
        ok = $false
        error = "repo_lock_active"
        lock_path = $path
        existing_lock = $existing
      }
    }
    $staleRecovered = $true
    $stalePath = "$path.stale.$((Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")).json"
    Move-Item -LiteralPath $path -Destination $stalePath -Force
  }

  $lock = [pscustomobject]@{
    ok = $true
    lock_path = $path
    task_id = [string]$Task.task_id
    worker_id = [string]$Config.worker_id
    pid = $PID
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    stale_recovered = $staleRecovered
  }
  $lock | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
  return $lock
}

function Remove-SkyBridgeRepoLock {
  param($Lock)
  if (-not $Lock -or -not $Lock.ok -or [string]::IsNullOrWhiteSpace([string]$Lock.lock_path)) { return $false }
  $existing = Read-SkyBridgeRepoLock -Path ([string]$Lock.lock_path)
  if (-not $existing) { return $true }
  if ([string]$existing.task_id -ne [string]$Lock.task_id -or [int]$existing.pid -ne [int]$Lock.pid) {
    return $false
  }
  Remove-Item -LiteralPath ([string]$Lock.lock_path) -Force -ErrorAction SilentlyContinue
  return $true
}

function Get-SkyBridgeGitPorcelainFiles {
  param([string]$RepoPath)
  $rows = @(git -C $RepoPath status --porcelain=v1 --untracked-files=normal)
  return @($rows | ForEach-Object {
    $line = [string]$_
    if ($line -match "^\s*(?:[AMDRCU?!]{1,2})\s+(.+)$") { $Matches[1].Trim('"') }
  } | Where-Object {
    $_ -and $_ -notmatch "^(?:\.agent/locks/|\.agent\\locks\\)"
  })
}

function Test-SkyBridgeDirtyTreeGuard {
  param($Config, $Task)
  $repoPath = Get-SkyBridgeRepoPath -Config $Config
  $files = @(Get-SkyBridgeGitPorcelainFiles -RepoPath $repoPath)
  return [pscustomobject]@{
    ok = ($files.Count -eq 0)
    guard = "dirty_tree"
    reason = $(if ($files.Count -eq 0) { $null } else { "repo_dirty_before_task_execution" })
    changed_files = $files
  }
}

function Test-SkyBridgeActivePrGuard {
  param($Config, $Task)
  $prUrl = if ($Task.result -and $Task.result.pr_url) { [string]$Task.result.pr_url } elseif ($Task.pr_url) { [string]$Task.pr_url } else { $null }
  return [pscustomobject]@{
    ok = [string]::IsNullOrWhiteSpace($prUrl)
    guard = "active_pr"
    reason = $(if ($prUrl) { "task_already_has_child_pr" } else { $null })
    pr_url = $prUrl
  }
}

function Test-SkyBridgeTaskLeaseGuard {
  param($Config, $Task)
  $lease = if ($Task -and $Task.PSObject.Properties["lease"]) { $Task.lease } else { $null }
  if (-not $lease) {
    return [pscustomobject]@{
      ok = $false
      guard = "task_lease"
      reason = "claimed_task_missing_active_lease"
      lease_status = $null
      lease_id = $null
    }
  }
  $workerId = if ($lease.worker_id) { [string]$lease.worker_id } else { $null }
  $leaseStatus = if ($lease.lease_status) { [string]$lease.lease_status } else { $null }
  $ok = ($leaseStatus -eq "active" -and $workerId -eq [string]$Config.worker_id)
  return [pscustomobject]@{
    ok = $ok
    guard = "task_lease"
    reason = $(if ($ok) { $null } else { "claimed_task_lease_not_active_for_worker" })
    lease_status = $leaseStatus
    lease_id = if ($lease.lease_id) { [string]$lease.lease_id } else { $null }
    lease_worker_id = $workerId
  }
}

function Test-SkyBridgeBranchGuard {
  param($Config, $Task)
  $repoPath = Get-SkyBridgeRepoPath -Config $Config
  $currentBranch = (git -C $repoPath branch --show-current)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
    return [pscustomobject]@{ ok = $false; guard = "active_branch"; reason = "current_branch_unknown"; current_branch = $currentBranch }
  }
  $branchPrefix = if ($Config.branch_prefix) { [string]$Config.branch_prefix } else { "ai/edge-worker/" }
  $taskBranch = if (Get-Command Get-SafeTaskBranchName -ErrorAction SilentlyContinue) {
    Get-SafeTaskBranchName -Config $Config -Task $Task
  } else {
    "$branchPrefix$($Task.task_id)"
  }
  if ($currentBranch.StartsWith($branchPrefix) -and $currentBranch -ne $taskBranch) {
    return [pscustomobject]@{
      ok = $false
      guard = "active_branch"
      reason = "worker_task_branch_belongs_to_different_task"
      current_branch = $currentBranch
      task_branch = $taskBranch
    }
  }
  git -C $repoPath show-ref --verify --quiet "refs/heads/$taskBranch"
  $branchExists = ($LASTEXITCODE -eq 0)
  if ($branchExists -and $currentBranch -ne $taskBranch) {
    return [pscustomobject]@{
      ok = $false
      guard = "branch_collision"
      reason = "task_branch_already_exists"
      current_branch = $currentBranch
      task_branch = $taskBranch
    }
  }
  return [pscustomobject]@{
    ok = $true
    guard = "active_branch"
    current_branch = $currentBranch
    task_branch = $taskBranch
  }
}

function Test-SkyBridgeWorkerTaskSafety {
  param($Config, $Task)
  $guards = @(
    (Test-SkyBridgeTaskLeaseGuard -Config $Config -Task $Task),
    (Test-SkyBridgeDirtyTreeGuard -Config $Config -Task $Task),
    (Test-SkyBridgeActivePrGuard -Config $Config -Task $Task),
    (Test-SkyBridgeBranchGuard -Config $Config -Task $Task)
  )
  $failed = @($guards | Where-Object { -not $_.ok })
  return [pscustomobject]@{
    ok = ($failed.Count -eq 0)
    guards = $guards
    failed_guards = @($failed | ForEach-Object { $_.guard })
    reason = $(if ($failed.Count -eq 0) { $null } else { ($failed | ForEach-Object { $_.reason } | Where-Object { $_ } | Select-Object -First 1) })
  }
}
