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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-submit-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-submit.sqlite"
$jsonFile = Join-Path $tempDir "submit.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  $dryRun = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
    -ApiBase $ApiBase `
    -ProjectId submit-project `
    -GoalId submit-goal `
    -GoalTitle "Submit Goal" `
    -TaskId submit-task `
    -TaskTitle "Submit Task" `
    -TaskBody "Docs-only submit smoke." `
    -EnsureProject `
    -EnsureGoal `
    -DryRun `
    -Json | ConvertFrom-Json
  if ($dryRun.mode -ne "dry-run" -or $dryRun.task.action -ne "would_create") { throw "Expected dry-run would_create task." }

  $apply = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
    -ApiBase $ApiBase `
    -ProjectId submit-project `
    -GoalId submit-goal `
    -GoalTitle "Submit Goal" `
    -TaskId submit-task `
    -TaskTitle "Submit Task" `
    -TaskBody "Docs-only submit smoke." `
    -EnsureProject `
    -EnsureGoal `
    -Apply `
    -Json `
    -OutputFile $jsonFile | ConvertFrom-Json
  if ($apply.mode -ne "apply" -or $apply.project.action -ne "created" -or $apply.goal.action -ne "created" -or $apply.task.action -ne "created") {
    throw "Expected apply to create project, goal and task."
  }
  if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) { throw "Expected submit output file." }
  $task = Invoke-SkyBridgeJson "GET" "/v1/tasks/submit-task"
  if ($task.task.required_capabilities[0] -ne "codex") { throw "Expected default codex capability." }
  if ($apply.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    DryRun = "passed"
    Apply = "passed"
    TaskId = $task.task.task_id
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
