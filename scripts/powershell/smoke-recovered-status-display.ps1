param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-recovered-status-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-recovered-status.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "recovered-project"; name = "Recovered Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "laptop-zenbookduo"; name = "Laptop" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/laptop-zenbookduo/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "operator-real-docs-task-170"; project_id = "recovered-project"; title = "Recovered fixture"; risk = "low"; source = "manual" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/operator-real-docs-task-170/claim" @{ worker_id = "laptop-zenbookduo" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/operator-real-docs-task-170/fail" @{ error_summary = "checkout 403" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/operator-real-docs-task-170/evidence-repair" @{
    summary = "Recovered after cloud server deployment"
    evidence_summary = @{
      task_id = "operator-real-docs-task-170"
      worker_id = "laptop-zenbookduo"
      pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/60"
      validation_status = "passed"
      ci_status = "passed_after_rerun"
      risk_status = "low"
      recovered = $true
      summary = "Child PR passed and merged after rerun."
    }
  } | Out-Null

  $compact = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId recovered-project -TaskId operator-real-docs-task-170
  $json = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId recovered-project -TaskId operator-real-docs-task-170 -Json | ConvertFrom-Json
  $task = @($json.tasks)[0]

  if (($compact -join "`n") -notmatch "display_status:\s+recovered") { throw "Expected human detail display_status=recovered." }
  if (($compact -join "`n") -notmatch "raw_status:\s+failed") { throw "Expected human detail raw_status=failed." }
  if ($task.raw_status -ne "failed" -or $task.display_status -ne "recovered" -or $task.ci_status -ne "passed_after_rerun" -or $task.recovered -ne $true) {
    throw "Expected JSON recovered display semantics."
  }
  if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    RawStatus = $task.raw_status
    DisplayStatus = $task.display_status
    Recovered = $task.recovered
    CiStatus = $task.ci_status
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
