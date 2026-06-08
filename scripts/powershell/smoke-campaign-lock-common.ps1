[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Scenario,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$control = Join-Path $PSScriptRoot "skybridge-dev-queue-control.ps1"

function Invoke-ControlJson {
  param([string[]]$Arguments)
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $control @Arguments -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "control command failed: $($raw -join "`n")" }
  return (($raw -join "`n") | ConvertFrom-Json)
}

function Assert-NoSecretText {
  param([string]$Text)
  if ($Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----') {
    throw "Secret-looking output detected."
  }
}

$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")

switch ($Scenario) {
  "contract" {
    foreach ($required in @("CampaignLock", "RepoExclusiveLock", "LockOwner", "CampaignPriorityQueue", "LockRecoveryDecision", "fixtureCampaignLock", "fixtureRepoExclusiveLock")) {
      if ($client -notmatch [regex]::Escape($required)) { throw "Missing lock contract symbol: $required" }
    }
    $status = Invoke-ControlJson @("-Command", "campaign-lock-status", "-Fixture")
    if ($status.campaign_lock.schema -ne "skybridge.campaign_lock.v1" -or $status.token_printed) { throw "Invalid campaign lock status." }
  }
  "active-block" {
    $preview = Invoke-ControlJson @("-Command", "start-one-preview", "-Fixture")
    if ($preview.allowed -or @($preview.blockers) -notcontains "active_repo_lock_blocks_execution_preview") { throw "Active repo lock did not block start preview." }
  }
  "stale-preview" {
    $preview = Invoke-ControlJson @("-Command", "campaign-lock-preview", "-Fixture")
    if ($preview.lock.lock_status -ne "stale" -or $preview.mode -ne "dry-run" -or $preview.task_created) { throw "Stale lock preview invalid." }
  }
  "stale-unlock-requires-reason" {
    $failed = $false
    try { Invoke-ControlJson @("-Command", "unlock-stale-campaign-lock", "-Fixture", "-Apply") | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "Stale unlock apply without reason must fail." }
    $apply = Invoke-ControlJson @("-Command", "unlock-stale-campaign-lock", "-Fixture", "-Apply", "-Reason", "smoke stale lock release")
    if (-not $apply.allowed -or $apply.lock.lock_status -ne "released" -or -not $apply.reason_recorded) { throw "Reasoned stale unlock apply failed." }
  }
  "active-unlock-refused" {
    $preview = Invoke-ControlJson @("-Command", "repo-lock-preview", "-Fixture")
    if ($preview.allowed -or @($preview.blockers) -notcontains "active_lock_force_release_refused") { throw "Active lock release was not refused." }
  }
  "repo-contract" {
    $status = Invoke-ControlJson @("-Command", "repo-lock-status", "-Fixture")
    if ($status.repo_exclusive_lock.schema -ne "skybridge.repo_exclusive_lock.v1" -or -not $status.repo_exclusive_lock.blocks_execution_preview) { throw "Invalid repo lock contract." }
  }
  "repo-blocks-preview" {
    $preview = Invoke-ControlJson @("-Command", "start-queue-preview", "-Fixture")
    if ($preview.allowed -or @($preview.blockers) -notcontains "active_repo_lock_blocks_execution_preview") { throw "Repo lock did not block queue preview." }
  }
  "priority-queue" {
    $queue = Invoke-ControlJson @("-Command", "campaign-priority-queue", "-Fixture")
    $priorities = @($queue.priority_queue.items | ForEach-Object { [int]$_.priority })
    if (-not $queue.priority_queue.one_active_campaign_per_project -or ($priorities -join ",") -ne "10,20") { throw "Priority queue is not deterministic." }
  }
  "select-next" {
    $selection = Invoke-ControlJson @("-Command", "campaign-select-next-preview", "-Fixture")
    if ($selection.queue_execution_enabled -or $selection.task_created -or $selection.selection.execution_side_effects) { throw "Selection preview had execution side effects." }
  }
  "cancel-abort-hold" {
    foreach ($command in @("cancel-campaign-preview", "abort-campaign-preview", "hold-campaign-preview")) {
      $failed = $false
      try { Invoke-ControlJson @("-Command", $command, "-Fixture") | Out-Null } catch { $failed = $true }
      if (-not $failed) { throw "$command without reason must fail." }
      $result = Invoke-ControlJson @("-Command", $command, "-Fixture", "-Reason", "smoke reason")
      if ($result.task_created -or $result.worker_loop_started -or $result.queue_execution_enabled) { throw "$command had execution side effects." }
    }
  }
  "desktop-panel" {
    foreach ($required in @("Campaign Lock Review", "repo_exclusive_lock", "Campaign Priority Queue", "Unlock apply requires reason", "Start controls disabled")) {
      if ($desktop -notmatch [regex]::Escape($required)) { throw "Desktop lock panel missing: $required" }
    }
  }
  "web-panel" {
    foreach ($required in @("Campaign / Repo Locks", "Priority Selection", "stale unlock apply requires operator reason", "No execution controls are exposed")) {
      if ($web -notmatch [regex]::Escape($required)) { throw "Web lock panel missing: $required" }
    }
  }
  "attention" {
    foreach ($required in @("active_repo_lock_blocks_queue", "stale_lock_requires_review", "campaign_held", "multi_campaign_conflict", "unlock_requires_reason")) {
      if ($client -notmatch [regex]::Escape($required)) { throw "Attention contract missing: $required" }
    }
  }
  "no-execution" {
    foreach ($command in @("campaign-lock-preview", "repo-lock-preview", "campaign-select-next-preview")) {
      $result = Invoke-ControlJson @("-Command", $command, "-Fixture")
      if ($result.task_created -or $result.worker_loop_started -or $result.queue_execution_enabled) { throw "$command had execution side effects." }
    }
    $start = Invoke-ControlJson @("-Command", "start-one", "-Fixture", "-Apply", "-Reason", "must stay disabled")
    if ($start.allowed) { throw "start-one apply became allowed." }
  }
  "no-secrets" {
    $campaignLock = Invoke-ControlJson @("-Command", "campaign-lock-status", "-Fixture")
    $repoLock = Invoke-ControlJson @("-Command", "repo-lock-status", "-Fixture")
    $queue = Invoke-ControlJson @("-Command", "campaign-priority-queue", "-Fixture")
    $outputs = @($campaignLock, $repoLock, $queue) | ConvertTo-Json -Depth 80 -Compress
    Assert-NoSecretText $outputs
    if ($outputs -notmatch '"token_printed":false') { throw "token_printed=false missing." }
  }
  "clean-worktree" {
    $before = (git status --short | Out-String).Trim()
    Invoke-ControlJson @("-Command", "campaign-lock-status", "-Fixture") | Out-Null
    Invoke-ControlJson @("-Command", "repo-lock-status", "-Fixture") | Out-Null
    $after = (git status --short | Out-String).Trim()
    if ($before -ne $after) { throw "Lock smokes changed git status." }
  }
  default { throw "Unknown campaign lock smoke scenario: $Scenario" }
}

$summary = [pscustomobject]@{
  ok = $true
  scenario = "campaign-lock-$Scenario"
  active_tasks = 0
  stale_leases = 0
  can_start_one = $false
  can_start_queue = $false
  task_created = $false
  worker_loop_started = $false
  queue_execution_enabled = $false
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
