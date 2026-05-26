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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-once-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-run-once.sqlite"
$profileFile = Join-Path $tempDir "worker.run-once.json"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "run-once-project"; name = "Run Once Project" } | Out-Null

  @{
    worker_id = "run-once-worker"
    display_name = "Run Once Worker"
    project_ids = @("run-once-project")
    allowed_project_ids = @("run-once-project")
    repo_paths = @{ "run-once-project" = (Resolve-Path ".").Path }
    capabilities = @("codex")
    executor_adapters = @("codex")
    preferred_task_types = @("docs")
    blocked_task_types = @()
    max_parallel_tasks = 1
    allow_auto_merge = $false
    allow_production_deploy = $false
    skybridge_api_base = $ApiBase
    auth_mode = "none"
    token_env_var = "SKYBRIDGE_WORKER_TOKEN"
    allow_remote_server = $false
    reject_insecure_http_for_remote = $true
    codex_command = "codex"
    codex_sandbox = "workspace-write"
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profileFile -Encoding UTF8

  $dryRun = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
    -ApiBase $ApiBase `
    -ProjectId run-once-project `
    -GoalId run-once-goal `
    -GoalTitle "Run Once Goal" `
    -TaskId run-once-task `
    -TaskTitle "Run Once Task" `
    -TaskBody "Docs-only run-once dry run." `
    -WorkerProfile $profileFile `
    -OutputDir $outputDir `
    -DryRun `
    -Json | ConvertFrom-Json
  if ($dryRun.mode -ne "dry-run" -or $dryRun.project_paused -ne "would_pause") { throw "Expected dry-run pause plan." }
  if (-not (Test-Path -LiteralPath (Join-Path $outputDir "skybridge-run-once-before.json") -PathType Leaf)) { throw "Expected before snapshot." }
  if (-not (Test-Path -LiteralPath (Join-Path $outputDir "skybridge-run-once-after.json") -PathType Leaf)) { throw "Expected after snapshot." }

  $apply = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
    -ApiBase $ApiBase `
    -ProjectId run-once-project `
    -WorkerProfile $profileFile `
    -OutputDir $outputDir `
    -NoSubmit `
    -Apply `
    -AllowDirty `
    -Json | ConvertFrom-Json
  if ($apply.project_started -ne "started" -or $apply.worker_checked -ne "register-heartbeat" -or $apply.project_paused -ne "paused") {
    throw "Expected apply to start, heartbeat and pause."
  }
  $control = Invoke-SkyBridgeJson "GET" "/v1/projects/run-once-project/control"
  if ($control.control_state.state -ne "paused" -or $control.control_state.stop_requested -ne $false) { throw "Expected restored paused control." }
  if ($apply.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    DryRun = "passed"
    ApplyNoTask = "passed"
    ProjectPaused = $control.control_state.state
    Snapshots = (Test-Path -LiteralPath (Join-Path $outputDir "skybridge-run-once-after.json") -PathType Leaf)
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
