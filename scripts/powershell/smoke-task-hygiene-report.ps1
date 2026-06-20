[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; return } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Assert-False($Value, [string]$Name) {
  if ($Value -ne $false) { throw "$Name must be false." }
}

function Assert-True($Value, [string]$Name) {
  if ($Value -ne $true) { throw "$Name must be true." }
}

function Assert-ContainsTask($Values, [string]$TaskId, [string]$Name) {
  if (@($Values | Where-Object { $_.task_id -eq $TaskId }).Count -lt 1) {
    throw "$Name missing task $TaskId."
  }
}

function Assert-NoRawOrSecretText([string]$Text) {
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  if ($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue") {
    throw "Unsafe text detected."
  }
  if ($Text -match "THIS_SHOULD_NOT_APPEAR|fixture raw prompt|fixture raw log") {
    throw "Raw prompt/log fixture marker leaked."
  }
}

function Get-TaskStateSnapshot {
  $response = Invoke-SkyBridgeJson "GET" "/v1/tasks?project_id=task-hygiene-project"
  @($response.tasks | Sort-Object task_id | ForEach-Object {
    [pscustomobject]@{
      task_id = $_.task_id
      status = $_.status
      assigned_worker_id = $_.assigned_worker_id
      updated_at = $_.updated_at
      result_json = if ($_.result) { ($_.result | ConvertTo-Json -Depth 16 -Compress) } else { $null }
      lease_json = if ($_.lease) { ($_.lease | ConvertTo-Json -Depth 16 -Compress) } else { $null }
    }
  })
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-task-hygiene-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-task-hygiene.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "task-hygiene-project"; name = "Task Hygiene Project" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/task-hygiene-project/control" @{ state = "paused"; stop_requested = $false; stop_reason = "task_hygiene_fixture" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "task-hygiene-worker"; name = "Task Hygiene Worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/task-hygiene-worker/heartbeat" @{ status_note = "ready" } | Out-Null

  foreach ($task in @(
    @{ task_id = "hygiene-failed"; project_id = "task-hygiene-project"; title = "Failed fixture"; risk = "low"; task_type = "docs"; source = "manual"; prompt_summary = "fixture raw prompt THIS_SHOULD_NOT_APPEAR" },
    @{ task_id = "hygiene-blocked"; project_id = "task-hygiene-project"; title = "Blocked fixture"; risk = "high"; task_type = "production"; source = "manual" },
    @{ task_id = "hygiene-needs-evidence"; project_id = "task-hygiene-project"; title = "Needs evidence fixture"; risk = "low"; task_type = "docs"; source = "manual" },
    @{ task_id = "hygiene-historical"; project_id = "task-hygiene-project"; title = "Historical blocked fixture"; risk = "low"; task_type = "docs"; source = "manual" },
    @{ task_id = "hygiene-stale-claim"; project_id = "task-hygiene-project"; title = "Stale claim fixture"; risk = "low"; task_type = "docs"; source = "manual" }
  )) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" $task | Out-Null
  }

  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-failed/claim" @{ worker_id = "task-hygiene-worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-failed/fail" @{ worker_id = "task-hygiene-worker"; error_summary = "fixture raw log THIS_SHOULD_NOT_APPEAR" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-blocked/block" @{ error_summary = "policy blocked" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-needs-evidence/claim" @{ worker_id = "task-hygiene-worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-needs-evidence/fail" @{ worker_id = "task-hygiene-worker"; error_summary = "merged pr needs evidence"; pr_url = "https://github.com/example/repo/pull/315" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-historical/block" @{ error_summary = "historical keep-blocked" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/hygiene-stale-claim/claim" @{ worker_id = "task-hygiene-worker" } | Out-Null

  $mutateScript = Join-Path $tempDir "mutate-stale-claim.mjs"
  Set-Content -LiteralPath $mutateScript -Encoding UTF8 -Value @"
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
const old = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
const row = db.prepare('SELECT task_json FROM tasks WHERE task_id = ?').get('hygiene-stale-claim');
if (!row) throw new Error('missing stale claim task');
const task = JSON.parse(row.task_json);
task.updated_at = old;
task.lease.lease_expires_at = old;
task.lease.heartbeat_at = old;
db.prepare('UPDATE tasks SET updated_at = ?, task_json = ? WHERE task_id = ?').run(task.updated_at, JSON.stringify(task), 'hygiene-stale-claim');
"@
  node $mutateScript $dbFile

  $before = Get-TaskStateSnapshot
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-hygiene-report.ps1 -ApiBase $ApiBase -ProjectId "task-hygiene-project" -Json
  if ($LASTEXITCODE -ne 0) { throw "task hygiene report script failed." }
  $text = (($raw | Out-String).Trim())
  Assert-NoRawOrSecretText $text
  $report = $text | ConvertFrom-Json
  $after = Get-TaskStateSnapshot

  if (($before | ConvertTo-Json -Depth 20 -Compress) -ne ($after | ConvertTo-Json -Depth 20 -Compress)) {
    throw "Task state changed during report."
  }

  if ($report.schema -ne "skybridge.task_hygiene_report.v1") { throw "Unexpected schema." }
  Assert-True $report.ok "ok"
  Assert-True $report.read_only "read_only"
  Assert-False $report.tasks_mutated "tasks_mutated"
  Assert-False $report.tasks_claimed "tasks_claimed"
  Assert-False $report.tasks_requeued "tasks_requeued"
  Assert-False $report.tasks_cancelled "tasks_cancelled"
  Assert-False $report.project_control_unpaused "project_control_unpaused"
  Assert-False $report.queue_apply_called "queue_apply_called"
  Assert-False $report.campaign_metadata_advanced "campaign_metadata_advanced"
  Assert-False $report.codex_run_called "codex_run_called"
  Assert-False $report.raw_logs_included "raw_logs_included"
  Assert-False $report.raw_prompts_included "raw_prompts_included"
  Assert-False $report.token_printed "token_printed"

  Assert-ContainsTask $report.unsafe_to_requeue_candidates "hygiene-failed" "unsafe_to_requeue_candidates"
  Assert-ContainsTask $report.unsafe_to_requeue_candidates "hygiene-blocked" "unsafe_to_requeue_candidates"
  Assert-ContainsTask $report.evidence_repair_candidates "hygiene-needs-evidence" "evidence_repair_candidates"
  Assert-ContainsTask $report.archive_or_keep_blocked_candidates "hygiene-historical" "archive_or_keep_blocked_candidates"

  $unsafeBlocked = @($report.task_classifications | Where-Object { $_.task_id -eq "hygiene-blocked" })[0]
  if ($unsafeBlocked.classification -ne "blocked-by-policy") { throw "Blocked unsafe task was not classified blocked-by-policy." }
  $historical = @($report.task_classifications | Where-Object { $_.task_id -eq "hygiene-historical" })[0]
  if ($historical.classification -ne "historical-residue") { throw "Historical task was not keep-blocked report-only residue." }
  $needsEvidence = @($report.task_classifications | Where-Object { $_.task_id -eq "hygiene-needs-evidence" })[0]
  if ($needsEvidence.classification -ne "evidence-repair-only" -or $needsEvidence.evidence.needs_repair -ne $true) { throw "Needs-evidence task was not classified evidence-repair-only." }
  $failed = @($report.task_classifications | Where-Object { $_.task_id -eq "hygiene-failed" })[0]
  if ($failed.classification -ne "unsafe-to-requeue") { throw "Failed task was not classified unsafe-to-requeue." }
  if (@($report.safe_requeue_candidates).Count -ne 0) { throw "Goal 315 report must not produce safe requeue candidates for this fixture." }

  $summary = [pscustomobject]@{
    ok = $true
    smoke = "task-hygiene-report"
    api_base = $ApiBase
    failed_unrecovered = $report.failed_unrecovered
    blocked = $report.blocked
    needs_evidence = $report.needs_evidence
    stale_claims = $report.stale_claims
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Write-Host "[smoke-task-hygiene-report] ok token_printed=false" }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
