param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-evidence-repair-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-evidence-repair.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "repair-project"; name = "Repair Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "repair-task"; project_id = "repair-project"; title = "Repair task" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "repair-worker"; name = "Repair worker"; capabilities = @("codex") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/repair-worker/heartbeat" @{ status_note = "repair smoke" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/repair-task/claim" @{ worker_id = "repair-worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/repair-task/fail" @{ worker_id = "repair-worker"; error_summary = "ci blocked"; pr_url = "https://example.invalid/pull/1" } | Out-Null
  $repaired = Invoke-SkyBridgeJson "POST" "/v1/tasks/repair-task/evidence-repair" @{
    worker_id = "repair-worker"
    pr_url = "https://example.invalid/pull/1"
    evidence_summary = @{
      task_id = "repair-task"
      pr_url = "https://example.invalid/pull/1"
      changed_files = @("docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md")
      validation_status = "passed"
      ci_status = "passed_after_rerun"
      risk_status = "low_docs_only"
      recovered = $true
      recovery_status = "merged_after_rerun"
      summary = "Recovered after CI rerun."
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  }
  $events = @($repaired.task.events | ForEach-Object { $_.type })
  if ($repaired.task.status -ne "failed") { throw "Expected original failed status to remain." }
  if ($events -notcontains "task.failed" -or $events -notcontains "task.evidence_repaired") { throw "Expected failure and repair events." }
  if ($repaired.task.result.evidence_summary.recovered -ne $true) { throw "Expected recovered evidence." }
  [pscustomobject]@{
    StatusPreserved = $repaired.task.status
    RecoveryEvent = $true
    Recovered = $repaired.task.result.evidence_summary.recovered
    CiStatus = $repaired.task.result.evidence_summary.ci_status
  } | Format-List
} finally {
  if ($serverProcess) { try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue } }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
