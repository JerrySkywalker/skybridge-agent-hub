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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-guide-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-guide.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "guide-project"; name = "Guide Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "guide-existing-task"; project_id = "guide-project"; title = "Existing"; risk = "low"; source = "manual" } | Out-Null

  $status = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode status -ApiBase $ApiBase -ProjectId guide-project -OutputDir $outputDir -Json | ConvertFrom-Json
  $submitPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode submit-preview -ApiBase $ApiBase -ProjectId guide-project -GoalId guide-goal -GoalTitle "Guide Goal" -TaskId guide-task -TaskTitle "Guide Task" -TaskBody "Docs dry run" -OutputDir $outputDir -Json | ConvertFrom-Json
  $runPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode run-once-preview -ApiBase $ApiBase -ProjectId guide-project -GoalId guide-goal -TaskId guide-existing-task -OutputDir $outputDir -Json | ConvertFrom-Json
  $inspect = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode inspect-task -ApiBase $ApiBase -ProjectId guide-project -TaskId guide-existing-task -OutputDir $outputDir -Json | ConvertFrom-Json

  if ($status.mode -ne "status" -or $status.token_printed -ne $false) { throw "Expected guide status result." }
  if ($submitPreview.submit.mode -ne "dry-run" -or $submitPreview.task_id -ne "guide-task") { throw "Expected guide submit-preview dry run." }
  if ($runPreview.run_once.mode -ne "dry-run" -or $runPreview.run_once.project_paused -ne "would_pause") { throw "Expected guide run-once-preview." }
  if (@($inspect.status.tasks).Count -ne 1 -or $inspect.status.tasks[0].task_id -ne "guide-existing-task") { throw "Expected guide inspect-task." }
  if (-not (Test-Path -LiteralPath (Join-Path $outputDir "skybridge-guide-status.json") -PathType Leaf)) { throw "Expected guide status snapshot." }

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
