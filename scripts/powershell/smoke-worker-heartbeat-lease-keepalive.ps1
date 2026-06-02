param(
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -eq "POST" -or $Method -eq "PATCH") {
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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-keepalive-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-keepalive.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "keepalive-project"; name = "Keepalive Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "keepalive-worker"; name = "Keepalive worker"; capabilities = @("tests") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/keepalive-worker/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "keepalive-task"
    project_id = "keepalive-project"
    title = "Keepalive smoke task"
    risk = "low"
    source = "manual"
  } | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/tasks/keepalive-task/claim" @{ worker_id = "keepalive-worker" } | Out-Null
  $started = Invoke-SkyBridgeJson "POST" "/v1/tasks/keepalive-task/start" @{ worker_id = "keepalive-worker" }
  $firstExpiry = [datetimeoffset]::Parse([string]$started.task.lease.lease_expires_at).UtcDateTime
  Start-Sleep -Milliseconds 1200
  $heartbeat = Invoke-SkyBridgeJson "POST" "/v1/workers/keepalive-worker/heartbeat" @{ status_note = "task-active:keepalive-task" }
  $renewedExpiry = [datetimeoffset]::Parse([string]$heartbeat.lease.lease_expires_at).UtcDateTime
  if ($renewedExpiry -le $firstExpiry) { throw "Expected worker heartbeat to renew active task lease." }
  $worker = Invoke-SkyBridgeJson "GET" "/v1/workers/keepalive-worker"
  if ($worker.worker.current_task_id -ne "keepalive-task") { throw "Expected worker status to show active task." }
  $completed = Invoke-SkyBridgeJson "POST" "/v1/tasks/keepalive-task/complete" @{ worker_id = "keepalive-worker"; summary = "Lease keepalive smoke completed." }
  if ($completed.task.lease.lease_status -ne "released") { throw "Expected completed task to release lease." }

  [pscustomobject]@{
    ok = $true
    first_expiry = $firstExpiry.ToString("o")
    renewed_expiry = $renewedExpiry.ToString("o")
    current_task_id = $worker.worker.current_task_id
    released_lease = $completed.task.lease.lease_status
    token_printed = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
