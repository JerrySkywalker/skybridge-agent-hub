[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("task-limit", "recent-tasks", "active-only", "task-status-filter", "worker-filter", "recovered-filter", "task-detail-event-limit", "json-output")]
  [string]$Scenario,
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

function Invoke-StatusJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-filter-project" -Json @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 failed for $Scenario." }
  return ($output | ConvertFrom-Json)
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-status-fixture-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-status.sqlite"
$jsonFile = Join-Path $tempDir "status-output.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "status-filter-project"; name = "Status Filter Project" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/status-filter-project/control" @{ state = "paused"; stop_requested = $false; stop_reason = "status_filter_fixture" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-a"; name = "Status Worker A" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-a/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-b"; name = "Status Worker B" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-b/heartbeat" @{ status_note = "ready" } | Out-Null

  foreach ($task in @(
    @{ task_id = "status-filter-queued"; project_id = "status-filter-project"; title = "Queued"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-running"; project_id = "status-filter-project"; title = "Running"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-claimed"; project_id = "status-filter-project"; title = "Claimed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-completed"; project_id = "status-filter-project"; title = "Completed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-failed"; project_id = "status-filter-project"; title = "Failed"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-recovered"; project_id = "status-filter-project"; title = "Recovered"; risk = "low"; source = "manual" },
    @{ task_id = "status-filter-blocked"; project_id = "status-filter-project"; title = "Blocked"; risk = "low"; source = "manual" }
  )) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" $task | Out-Null
  }

  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-running/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-running/start" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-claimed/claim" @{ worker_id = "status-worker-b" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-completed/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-completed/complete" @{ worker_id = "status-worker-a"; summary = "done" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-failed/claim" @{ worker_id = "status-worker-a" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-failed/fail" @{ worker_id = "status-worker-a"; error_summary = "fixture failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/claim" @{ worker_id = "status-worker-b" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/fail" @{ worker_id = "status-worker-b"; error_summary = "fixture transient failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-recovered/evidence-repair" @{
    worker_id = "status-worker-b"
    summary = "Recovered after rerun"
    evidence_summary = @{
      task_id = "status-filter-recovered"
      pr_url = "https://github.com/example/repo/pull/2"
      validation_status = "passed"
      ci_status = "passed_after_rerun"
      risk_status = "low"
      recovered = $true
      summary = "Recovered fixture"
    }
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-filter-blocked/block" @{ error_summary = "fixture block" } | Out-Null

  switch ($Scenario) {
    "task-limit" {
      $status = Invoke-StatusJson -Arguments @("-TaskLimit", "2", "-ShowCompleted")
      if (@($status.tasks).Count -ne 2) { throw "Expected exactly two shown tasks." }
      if ($status.filters.truncated -ne $true) { throw "Expected truncated=true." }
    }
    "recent-tasks" {
      $status = Invoke-StatusJson -Arguments @("-RecentTasks", "3", "-ShowCompleted")
      if (@($status.tasks).Count -ne 3) { throw "Expected exactly three recent tasks." }
      if ($status.filters.recent_tasks -ne 3) { throw "Expected recent_tasks=3." }
    }
    "active-only" {
      $status = Invoke-StatusJson -Arguments @("-ActiveOnly")
      if (@($status.tasks).Count -lt 3) { throw "Expected queued, claimed and running tasks." }
      foreach ($task in @($status.tasks)) {
        if ($task.raw_status -notin @("queued", "claimed", "running")) { throw "ActiveOnly returned $($task.raw_status)." }
      }
      if ($status.task_summary.active -lt 3) { throw "Expected active summary count." }
    }
    "task-status-filter" {
      $status = Invoke-StatusJson -Arguments @("-TaskStatus", "failed", "-ExcludeRecovered", "-ShowAll")
      if (@($status.tasks).Count -ne 1) { throw "Expected only one unrecovered failed task." }
      if (@($status.tasks)[0].task_id -ne "status-filter-failed") { throw "Expected unrecovered failed task." }
    }
    "worker-filter" {
      $status = Invoke-StatusJson -Arguments @("-WorkerId", "status-worker-a", "-ShowAll")
      if (@($status.workers).Count -ne 1 -or @($status.workers)[0].worker_id -ne "status-worker-a") { throw "Expected selected worker only." }
      foreach ($task in @($status.tasks)) {
        if ($task.worker_id -ne "status-worker-a") { throw "Worker filter returned task assigned to $($task.worker_id)." }
      }
    }
    "recovered-filter" {
      $status = Invoke-StatusJson -Arguments @("-RecoveredOnly", "-TaskLimit", "20")
      if (@($status.tasks).Count -ne 1) { throw "Expected exactly one recovered task." }
      if (@($status.tasks)[0].display_status -ne "recovered") { throw "Expected recovered display status." }
    }
    "task-detail-event-limit" {
      $status = Invoke-StatusJson -Arguments @("-TaskId", "status-filter-recovered", "-EventLimit", "2")
      if (@($status.tasks).Count -ne 1) { throw "Expected one task detail." }
      $task = @($status.tasks)[0]
      if (@($task.events).Count -gt 2) { throw "Expected events to respect EventLimit." }
      if ($task.event_count -lt 2) { throw "Expected fixture to have multiple events." }
    }
    "json-output" {
      $status = Invoke-StatusJson -Arguments @("-TaskLimit", "3", "-OutputFile", $jsonFile)
      if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) { throw "Expected output file." }
      $fileStatus = Get-Content -Raw -LiteralPath $jsonFile | ConvertFrom-Json
      if ($fileStatus.token_printed -ne $false -or $status.token_printed -ne $false) { throw "Expected token_printed=false." }
      if (@($fileStatus.tasks).Count -ne @($status.tasks).Count) { throw "Expected JSON output file to match stdout shape." }
    }
  }

  $summary = [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    api_base = $ApiBase
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
