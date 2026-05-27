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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-guided-workflow-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-guided-workflow.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  $submitApply = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
    -Mode submit-apply `
    -ApiBase $ApiBase `
    -ProjectId guided-project `
    -GoalId guided-goal `
    -GoalTitle "Guided Goal" `
    -TaskId guided-task `
    -TaskTitle "Guided Task" `
    -TaskBody "Docs-only guided workflow fixture." `
    -Apply `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  if ($submitApply.submit.mode -ne "apply" -or $submitApply.submit.project.action -ne "created" -or $submitApply.submit.task.action -ne "created") {
    throw "Expected guide submit-apply to create project/goal/task."
  }

  $runPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
    -Mode run-once-preview `
    -ApiBase $ApiBase `
    -ProjectId guided-project `
    -GoalId guided-goal `
    -TaskId guided-task `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  if ($runPreview.run_once.mode -ne "dry-run" -or $runPreview.run_once.project_paused -ne "would_pause") {
    throw "Expected dry-run run-once preview."
  }

  $pause = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode pause -ApiBase $ApiBase -ProjectId guided-project -Json | ConvertFrom-Json
  if ($pause.control.control.state -ne "paused") { throw "Expected guide pause." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    SubmitApply = "passed"
    RunOncePreview = "passed"
    Pause = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
