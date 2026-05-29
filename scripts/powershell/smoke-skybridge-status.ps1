param(
  [int]$Port = 0
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
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-status-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-status.sqlite"
$jsonFile = Join-Path $tempDir "status.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{
    project_id = "status-project"
    name = "Status Project"
  } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/status-project/control" @{
    state = "paused"
    stop_requested = $false
    stop_reason = "smoke_paused"
  } | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-online"; name = "Online worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-online/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-offline"; name = "Offline worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "status-worker-stale"; name = "Stale worker" } | Out-Null
  $staleSeenAt = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString("o")
  Invoke-SkyBridgeJson "POST" "/v1/workers/status-worker-stale/heartbeat" @{ status_note = "stale"; seen_at = $staleSeenAt } | Out-Null

  foreach ($task in @(
    @{ task_id = "status-task-queued"; project_id = "status-project"; title = "Queued"; risk = "low"; source = "manual" },
    @{ task_id = "status-task-running"; project_id = "status-project"; title = "Running"; risk = "low"; source = "manual" },
    @{ task_id = "status-task-completed"; project_id = "status-project"; title = "Completed"; risk = "low"; source = "manual" },
    @{ task_id = "status-task-failed"; project_id = "status-project"; title = "Failed"; risk = "low"; source = "manual" },
    @{ task_id = "status-task-recovered"; project_id = "status-project"; title = "Recovered"; risk = "low"; source = "manual" },
    @{ task_id = "status-task-blocked"; project_id = "status-project"; title = "Blocked"; risk = "low"; source = "manual" }
  )) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" $task | Out-Null
  }
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-running/claim" @{ worker_id = "status-worker-online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-running/start" @{ worker_id = "status-worker-online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-completed/claim" @{ worker_id = "status-worker-online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-completed/complete" @{ summary = "done" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-failed/claim" @{ worker_id = "status-worker-online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-failed/fail" @{ error_summary = "fixture failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-recovered/claim" @{ worker_id = "status-worker-online" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-recovered/fail" @{ error_summary = "fixture transient failure" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-recovered/evidence-repair" @{
    summary = "Recovered after rerun"
    evidence_summary = @{
      task_id = "status-task-recovered"
      pr_url = "https://github.com/example/repo/pull/1"
      validation_status = "passed"
      ci_status = "passed_after_rerun"
      risk_status = "low"
      recovered = $true
      summary = "Recovered fixture"
    }
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/status-task-blocked/block" @{ error_summary = "fixture block" } | Out-Null

  $compact = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project"
  $compactCompleted = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project" -ShowCompleted
  $compactTask = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project" -TaskId "status-task-completed"
  $compactRecoveredTask = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project" -TaskId "status-task-recovered"
  $compactWorker = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project" -WorkerId "status-worker-online"
  $json = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId "status-project" -ShowCompleted -Json -OutputFile $jsonFile
  $parsed = $json | ConvertFrom-Json

  foreach ($expected in @("SkyBridge:", "Control:", "status-worker-online", "status-task-queued", "status-task-blocked")) {
    if (($compact -join "`n") -notmatch [regex]::Escape($expected)) {
      throw "Compact status output missing '$expected'."
    }
  }
  if (($compact -join "`n") -match "status-task-completed") { throw "Default compact output should hide completed tasks." }
  if (($compactCompleted -join "`n") -notmatch "status-task-completed") { throw "ShowCompleted should include completed tasks." }
  if (($compactTask -join "`n") -notmatch "status-task-completed") { throw "TaskId detail should show the selected task." }
  if (($compactRecoveredTask -join "`n") -notmatch "display_status:\s+recovered") { throw "Recovered task detail should show display_status=recovered." }
  if (($compactWorker -join "`n") -notmatch "status-worker-online") { throw "WorkerId detail should show the selected worker." }
  if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) { throw "Expected JSON output file." }
  if ($parsed.project_id -ne "status-project") { throw "Expected JSON project id." }
  if (@($parsed.workers).Count -lt 2) { throw "Expected worker rows." }
  $onlineWorker = @($parsed.workers | Where-Object { $_.worker_id -eq "status-worker-online" })[0]
  if (-not $onlineWorker.last_seen -or $onlineWorker.last_seen -notmatch "^[0-9]+s ago$|^[0-1]m ago$") {
    throw "Expected recent relative time after heartbeat, got '$($onlineWorker.last_seen)'."
  }
  $staleWorker = @($parsed.workers | Where-Object { $_.worker_id -eq "status-worker-stale" })[0]
  if (-not $staleWorker.last_seen -or $staleWorker.last_seen -notmatch "^[2-9]m ago$|^1[0-5]m ago$") {
    $workerDebug = @($parsed.workers | ForEach-Object { "$($_.worker_id):$($_.status):$($_.last_seen)" }) -join ", "
    throw "Expected minute-scale relative time for stale heartbeat, got '$($staleWorker.last_seen)'. Workers: $workerDebug"
  }
  if (@($parsed.tasks | Where-Object { $_.status -eq "completed" }).Count -lt 1) { throw "Expected completed task row." }
  $recoveredTask = @($parsed.tasks | Where-Object { $_.task_id -eq "status-task-recovered" })[0]
  if ($recoveredTask.raw_status -ne "failed" -or $recoveredTask.display_status -ne "recovered" -or $recoveredTask.recovered -ne $true) {
    throw "Expected recovered display semantics for failed recovered task."
  }
  if ($parsed.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    CompactOutput = "passed"
    JsonOutput = "passed"
    DetailFilters = "passed"
    Workers = @($parsed.workers).Count
    Tasks = @($parsed.tasks).Count
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
