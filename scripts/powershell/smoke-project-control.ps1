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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-control-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-control.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "control-project"; name = "Control Project" } | Out-Null

  $status = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command status -ApiBase $ApiBase -ProjectId control-project -Json | ConvertFrom-Json
  $start = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command start -ApiBase $ApiBase -ProjectId control-project -MaxTasks 3 -Json | ConvertFrom-Json
  $maxTasks = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command set-max-tasks -ApiBase $ApiBase -ProjectId control-project -MaxTasks 5 -Json | ConvertFrom-Json
  $pauseText = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command pause -ApiBase $ApiBase -ProjectId control-project
  $pause = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command status -ApiBase $ApiBase -ProjectId control-project -Json | ConvertFrom-Json
  $stop = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 -Command stop -ApiBase $ApiBase -ProjectId control-project -Json | ConvertFrom-Json

  if ($status.token_printed -ne $false) { throw "Expected token_printed=false." }
  if ($start.control.state -ne "running" -or $start.control.max_tasks -ne 3) { throw "Expected running max_tasks=3." }
  if ($maxTasks.control.max_tasks -ne 5) { throw "Expected max_tasks=5." }
  if ($pause.control.state -ne "paused" -or $pause.control.stop_requested -ne $false) { throw "Expected paused without stop request." }
  if (($pauseText -join "`n") -notmatch "State:") { throw "Expected compact control output." }
  if ($stop.control.state -ne "stopped" -or $stop.control.stop_requested -ne $true) { throw "Expected stopped with stop request." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Status = "passed"
    Start = "passed"
    SetMaxTasks = "passed"
    Pause = "passed"
    Stop = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
