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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-operator-workflow-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-operator-workflow.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  $statusBefore = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId workflow-project -Json | ConvertFrom-Json
  $submit = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
    -ApiBase $ApiBase `
    -ProjectId workflow-project `
    -GoalId workflow-goal `
    -GoalTitle "Workflow Goal" `
    -TaskId workflow-task `
    -TaskTitle "Workflow Task" `
    -TaskBody "Docs-only workflow smoke." `
    -EnsureProject `
    -EnsureGoal `
    -Apply `
    -Json | ConvertFrom-Json
  $runOnce = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
    -ApiBase $ApiBase `
    -ProjectId workflow-project `
    -GoalId workflow-goal `
    -TaskId workflow-task `
    -NoSubmit `
    -DryRun `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  $statusAfter = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId workflow-project -ShowAll -Json | ConvertFrom-Json

  if ($statusBefore.token_printed -ne $false -or $submit.token_printed -ne $false -or $runOnce.token_printed -ne $false -or $statusAfter.token_printed -ne $false) {
    throw "Expected token_printed=false across workflow."
  }
  if ($submit.task.action -ne "created") { throw "Expected workflow task creation." }
  if (@($statusAfter.tasks | Where-Object { $_.task_id -eq "workflow-task" }).Count -ne 1) { throw "Expected workflow task in status." }
  if ($runOnce.project_paused -ne "would_pause") { throw "Expected dry-run pause plan." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    StatusBefore = "passed"
    Submit = "passed"
    RunOnceDryRun = "passed"
    StatusAfter = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
