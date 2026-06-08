param(
  [string]$Scenario = "default",
  [string[]]$ExpectedReasons = @(),
  [switch]$ExpectSelected,
  [switch]$ExpectNoSelected,
  [switch]$ExpectRepoBlocked,
  [switch]$CheckCleanWorktree
)

$ErrorActionPreference = "Stop"

$before = (git status --short | Out-String).Trim()
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-worker-routing.ps1" -Command worker-route-preview -Scenario $Scenario -Json | ConvertFrom-Json
$json = $result | ConvertTo-Json -Depth 80 -Compress

if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }
foreach ($flag in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "queue_execution_enabled")) {
  if ($result.$flag -ne $false) { throw "Expected $flag=false." }
}
if ($ExpectSelected -and -not $result.selected_worker) { throw "Expected selected preview worker." }
if ($ExpectNoSelected -and $result.selected_worker) { throw "Expected no selected worker." }
if ($ExpectRepoBlocked -and $result.repo_parallelism_guard.blocked -ne $true) { throw "Expected repo parallelism guard to block." }
foreach ($reason in $ExpectedReasons) {
  if ($json -notmatch [regex]::Escape($reason)) { throw "Expected routing reason '$reason'." }
}
if ($json -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
  throw "Secret-looking or raw-log field detected."
}
if ($CheckCleanWorktree) {
  $after = (git status --short | Out-String).Trim()
  if ($before -ne $after) { throw "Worker routing smoke dirtied git status. Before=[$before] After=[$after]" }
}

[pscustomobject]@{
  ok = $true
  scenario = $Scenario
  selected_worker = $result.selected_worker.worker_id
  rejected_workers = @($result.rejected_workers).Count
  task_claimed = $result.task_claimed
  task_executed = $result.task_executed
  worker_loop_started = $result.worker_loop_started
  token_printed = $false
} | ConvertTo-Json -Compress
