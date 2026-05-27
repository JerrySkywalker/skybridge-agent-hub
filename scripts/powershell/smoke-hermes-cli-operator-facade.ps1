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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-facade-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-hermes-facade.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "facade-project"; name = "Facade Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "facade-task"; project_id = "facade-project"; title = "Facade Task"; risk = "low"; source = "manual" } | Out-Null

  $status = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 -Area operator -Command status -ApiBase $ApiBase -ProjectId facade-project -Json | ConvertFrom-Json
  $submitPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 -Area operator -Command submit-preview -ApiBase $ApiBase -ProjectId facade-project -GoalId facade-goal -GoalTitle "Facade Goal" -TaskId facade-new-task -TaskTitle "Facade New Task" -TaskBody "Docs dry run." -Json | ConvertFrom-Json
  $runPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 -Area operator -Command run-once-preview -ApiBase $ApiBase -ProjectId facade-project -GoalId facade-goal -TaskId facade-task -Json | ConvertFrom-Json
  $inspect = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 -Area operator -Command inspect-task -ApiBase $ApiBase -ProjectId facade-project -TaskId facade-task -Json | ConvertFrom-Json

  if ($status.mode -ne "status" -or $status.token_printed -ne $false) { throw "Expected operator status facade." }
  if ($submitPreview.mode -ne "submit-preview" -or $submitPreview.submit.mode -ne "dry-run") { throw "Expected operator submit-preview facade." }
  if ($runPreview.mode -ne "run-once-preview" -or $runPreview.run_once.mode -ne "dry-run") { throw "Expected operator run-once-preview facade." }
  if (@($inspect.status.tasks).Count -ne 1 -or $inspect.status.tasks[0].task_id -ne "facade-task") { throw "Expected operator inspect-task facade." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Status = "passed"
    SubmitPreview = "passed"
    RunOncePreview = "passed"
    InspectTask = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
