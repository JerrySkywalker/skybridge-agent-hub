param([int]$Port = 0)

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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-edge-worker-claim-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-edge-worker-claim.sqlite"
$configFile = Join-Path $tempDir "edge-worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "smoke-project"; name = "Smoke Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects/smoke-project/goals" @{ goal_id = "smoke-goal"; title = "Smoke goal" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "smoke-docs-task"
    project_id = "smoke-project"
    goal_id = "smoke-goal"
    title = "Docs smoke task"
    prompt_summary = "Docs-only claim smoke."
    risk = "low"
    source = "manual"
    required_capabilities = @("docs")
  } | Out-Null

  @{
    worker_id = "smoke-edge-worker"
    name = "Smoke Edge Worker"
    project_id = "smoke-project"
    repo_path = (Resolve-Path ".").Path
    api_base = $ApiBase
    poll_interval_seconds = 5
    capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
    allowed_task_types = @("docs")
    blocked_task_types = @("deploy", "secrets", "production")
    codex_command = "codex"
    codex_sandbox = "danger-full-access"
    max_task_runtime_minutes = 5
    auto_merge_enabled = $false
    notification_enabled = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configFile -Encoding UTF8

  pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -Register -Heartbeat -Json | Out-Null
  $preview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -PollOnce -DryRun -Json | ConvertFrom-Json
  $previewStep = @($preview.steps | Where-Object { $_.step -eq "claim" })[0]
  if ($previewStep.status -ne "preview" -or $previewStep.preview.task_id -ne "smoke-docs-task") {
    throw "Expected dry-run claim preview for smoke-docs-task."
  }

  $claim = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -PollOnce -ClaimOnly -Json | ConvertFrom-Json
  if (-not $claim.ok -or $claim.task_id -ne "smoke-docs-task") { throw "Expected claim-only worker run to claim smoke-docs-task." }
  $task = Invoke-SkyBridgeJson "GET" "/v1/tasks/smoke-docs-task"
  if ($task.task.status -ne "claimed") { throw "Expected claimed task, got $($task.task.status)." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    PreviewTask = $previewStep.preview.task_id
    ClaimedTask = $task.task.task_id
    Status = $task.task.status
    CodexExecuted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
