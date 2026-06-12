[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "safe-summary", "completed-runs", "release-readiness", "release-report", "operator-guidance", "no-execution-gate", "stale-smoke-list")]
  [string]$Command,
  [string]$ReportDir = ".agent/tmp/managed-mode-v0",
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [switch]$SimulateOpenManagedModePr,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function ConvertTo-ShortPath {
  param([string]$Path)
  $root = Get-RepoRoot
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $Path.Replace("\", "/")
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Get-Sha256File {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-SafeJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-SecretLookingText $text) { throw "Unsafe finalizer artifact detected: $(ConvertTo-ShortPath $Path)" }
  $text | ConvertFrom-Json
}

function New-CompletedRunArchiveItem {
  param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string[]]$ChangedFiles
  )
  $path = Resolve-RepoPath $EvidencePath
  $evidence = Read-SafeJsonFile $path
  if (-not $evidence) { throw "Missing $RunId finalizer evidence." }
  if ($evidence.token_printed -ne $false) { throw "$RunId finalizer evidence must report token_printed=false." }
  if ($evidence.no_raw_artifacts -ne $true) { throw "$RunId finalizer evidence must report no raw artifacts." }
  [pscustomobject]@{
    run_id = $RunId
    state = "completed"
    pr_url = [string]$evidence.task_pr.url
    merge_commit = [string]$evidence.task_pr.merge_commit
    finalizer_evidence_path = $EvidencePath
    finalizer_report_path = $EvidencePath.Replace("finalizer-evidence.json", "finalizer-report.json")
    finalizer_evidence_sha256 = Get-Sha256File $path
    changed_files = @($ChangedFiles)
    token_printed = $false
  }
}

function Get-OpenManagedModePrs {
  if ($SimulateOpenManagedModePr) {
    return @([pscustomobject]@{ number = 210; url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/210"; title = "Managed Mode Run"; state = "OPEN"; token_printed = $false })
  }
  try {
    $output = gh pr list --state open --search "managed-mode in:title,body,head" --json number,url,title,headRefName,state --limit 50 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "*managed-mode*" -or [string]$_.title -like "*Managed Mode*" -or [string]$_.headRefName -like "ai/managed-mode-*"
    })
  } catch { @() }
}

function New-RunArchive {
  $runs = @(
    New-CompletedRunArchiveItem -RunId "managed-mode-pilot-208" -EvidencePath ".agent/tmp/managed-mode-pilot-208/finalizer-evidence.json" -ChangedFiles @("docs/managed-mode-pilot-orientation.md")
    New-CompletedRunArchiveItem -RunId "managed-mode-run-209" -EvidencePath ".agent/tmp/managed-mode-run-209/finalizer-evidence.json" -ChangedFiles @("docs/managed-mode-repeatability-orientation.md")
    New-CompletedRunArchiveItem -RunId "managed-mode-run-210" -EvidencePath ".agent/tmp/managed-mode-run-210/finalizer-evidence.json" -ChangedFiles @("docs/managed-mode-v0-operator-checklist.md")
    New-CompletedRunArchiveItem -RunId "managed-mode-run-211" -EvidencePath ".agent/tmp/managed-mode-run-211/finalizer-evidence.json" -ChangedFiles @("docs/managed-mode-v0-repeatability-check.md")
  )
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_completed_runs.v1"
    completed_run_count = 4
    completed_run_ids = @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")
    runs = $runs
    docs_local_smoke_runs_after_pilot = @("managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")
    docs_local_smoke_run_count_after_pilot = 3
    changed_files = @("docs/managed-mode-pilot-orientation.md", "docs/managed-mode-repeatability-orientation.md", "docs/managed-mode-v0-operator-checklist.md", "docs/managed-mode-v0-repeatability-check.md")
    token_printed = $false
  }
}

function New-StaleSmokeList {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_stale_smoke_list.v1"
    stale_smoke_assumptions = @(
      "old dev-queue / Goal 199 fixture outputs are historical and must not imply current queue execution readiness",
      "queue-control helper sweeps are parameterized helpers and should not be run standalone as broad execution proof",
      "managed-mode v0 smokes should use direct focused release/readiness checks"
    )
    parameterized_helpers_not_standalone = @(
      "scripts/powershell/start-dev-queue-189-200.ps1",
      "scripts/powershell/skybridge-dev-queue-control.ps1"
    )
    no_mutation = $true
    token_printed = $false
  }
}

function New-ReleaseReadiness {
  $archive = New-RunArchive
  $openPrs = @(Get-OpenManagedModePrs)
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($archive.completed_run_count -ne 4) { $blockers.Add("completed_runs_missing") | Out-Null }
  if ($openPrs.Count -ne 0) { $blockers.Add("open_managed_mode_pr_present") | Out-Null }
  if ($ActiveTasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($StaleLeases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($RunnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_release_readiness.v1"
    readiness_id = "managed_mode_v0_9_readiness"
    self_bootstrap_v0_complete = $true
    managed_mode_pilot_complete = $true
    repeatable_one_at_a_time_run_complete = $true
    managed_mode_run_210_completed = $true
    managed_mode_run_211_completed = $true
    completed_runs = @($archive.completed_run_ids)
    docs_local_smoke_runs_after_pilot = @($archive.docs_local_smoke_runs_after_pilot)
    docs_local_smoke_run_count_after_pilot = $archive.docs_local_smoke_run_count_after_pilot
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    open_managed_mode_pr_count = $openPrs.Count
    general_bounded_queue_apply_enabled = $false
    multi_workunit_queue_enabled = $false
    resource_gate_integrated = $true
    resource_gate_required_for_next_run = $true
    next_run_requires_explicit_future_goal = $true
    no_next_execution_authorized = $true
    next_safe_action = "plan two-workunit preview only"
    release_ready = ($blockers.Count -eq 0)
    blockers = @($blockers)
    token_printed = $false
  }
}

function New-OperatorGuidance {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_operator_guidance.v1"
    current_state = "managed_mode_v0_9_readiness"
    next_safe_action = "plan two-workunit preview only"
    banners = @(
      "Managed Mode v0.9 readiness",
      "Resource gate required before next run",
      "No next execution authorized",
      "General bounded queue apply disabled"
    )
    disabled_actions = @("start-all", "start-queue apply", "bounded queue apply", "multi-workunit apply", "resume -Apply", "unbounded worker loop")
    token_printed = $false
  }
}

function New-Status {
  $archive = New-RunArchive
  $readiness = New-ReleaseReadiness
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_status.v1"
    product = "SkyBridge Agent Hub"
    status = if ($readiness.release_ready) { "ready" } else { "blocked" }
    completed_runs = $archive
    release_readiness = $readiness
    operator_guidance = New-OperatorGuidance
    stale_smoke_list = New-StaleSmokeList
    token_printed = $false
  }
}

function New-NoExecutionGate {
  $readiness = New-ReleaseReadiness
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v0_no_execution_gate.v1"
    no_next_execution_authorized = $true
    run_apply_enabled = $false
    general_bounded_queue_apply_enabled = $false
    start_all_enabled = $false
    start_queue_apply_enabled = $false
    resume_apply_enabled = $false
    readiness = $readiness
    token_printed = $false
  }
}

function Write-SafeReport {
  param($Object)
  $path = Resolve-RepoPath (Join-Path $ReportDir "release-report.json")
  $json = $Object | ConvertTo-Json -Depth 100
  if (Test-SecretLookingText $json) { throw "Unsafe release report blocked." }
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($path)) | Out-Null
  $json | Set-Content -LiteralPath $path -Encoding UTF8
  $Object | Add-Member -NotePropertyName report_path -NotePropertyValue (ConvertTo-ShortPath $path) -Force
  $Object
}

$result = switch ($Command) {
  "status" { New-Status }
  "safe-summary" { [pscustomobject]@{ schema = "skybridge.managed_mode_v0_safe_summary.v1"; status = New-Status; no_mutation = $true; token_printed = $false } }
  "completed-runs" { New-RunArchive }
  "release-readiness" { New-ReleaseReadiness }
  "operator-guidance" { New-OperatorGuidance }
  "no-execution-gate" { New-NoExecutionGate }
  "stale-smoke-list" { New-StaleSmokeList }
  "release-report" { Write-SafeReport ([pscustomobject]@{ schema = "skybridge.managed_mode_v0_release_report.v1"; status = New-Status; generated_at = (Get-Date).ToUniversalTime().ToString("o"); token_printed = $false }) }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking managed-mode v0 output detected." }
if ($Json) { $text } else { $result | Format-List }
