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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-codex-transport-retry-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge.sqlite"
$repoPath = Join-Path $tempDir "repo"
$remotePath = Join-Path $tempDir "origin.git"
$fakeCodex = Join-Path $tempDir "fake-codex.ps1"
$fakeMarker = Join-Path $tempDir "fake-codex-attempt.txt"
$profileFile = Join-Path $tempDir "worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  git init --initial-branch=main $repoPath | Out-Null
  git -C $repoPath config user.email "skybridge@example.invalid"
  git -C $repoPath config user.name "SkyBridge Smoke"
  "fixture" | Set-Content -LiteralPath (Join-Path $repoPath "README.md") -Encoding UTF8
  git -C $repoPath add README.md | Out-Null
  git -C $repoPath commit -m "init" | Out-Null
  git clone --bare $repoPath $remotePath | Out-Null
  git -C $repoPath remote add origin $remotePath
  git -C $repoPath fetch origin main | Out-Null

  @'
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)
$marker = Join-Path (Get-Location) ".fake-codex-attempt"
if ($env:SKYBRIDGE_FAKE_CODEX_MARKER) { $marker = $env:SKYBRIDGE_FAKE_CODEX_MARKER }
if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
  "1" | Set-Content -LiteralPath $marker -Encoding UTF8
  [Console]::Error.WriteLine("failed to connect to websocket: IO error: tls handshake eof, url: wss://chatgpt.com/backend-api/codex/responses")
  exit 1
}
"2" | Set-Content -LiteralPath $marker -Encoding UTF8
exit 0
'@ | Set-Content -LiteralPath $fakeCodex -Encoding UTF8

  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  $env:SKYBRIDGE_FAKE_CODEX_MARKER = $fakeMarker

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "transport-retry-project"; name = "Transport Retry Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "transport-retry-task"
    project_id = "transport-retry-project"
    title = "Transport retry task"
    prompt_summary = "Exercise one Codex transport retry."
    body = "No file changes required."
    task_type = "docs"
    required_capabilities = @("codex")
  } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/transport-retry-project/control" @{ state = "running"; stop_requested = $false; max_tasks = 1 } | Out-Null

  @{
    worker_id = "transport-retry-worker"
    display_name = "Transport Retry Worker"
    project_ids = @("transport-retry-project")
    repo_paths = @{ "transport-retry-project" = $repoPath }
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
    codex_command = $fakeCodex
    codex_sandbox = "workspace-write"
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profileFile -Encoding UTF8

  $result = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
    -ConfigFile $profileFile `
    -ProjectId transport-retry-project `
    -TaskId transport-retry-task `
    -Register `
    -PollOnce `
    -Json | ConvertFrom-Json

  if (-not $result.ok) { throw "Expected edge worker retry smoke to complete." }
  $executeStep = @($result.steps | Where-Object { $_.step -eq "execute" })[0]
  if (-not $executeStep -or $executeStep.retry_count -ne 1) { throw "Expected one Codex transport retry." }
  if ($executeStep.result.execution_error_class) { throw "Expected successful retry to clear final execution error class." }
  $retryStep = @($result.steps | Where-Object { $_.step -eq "execute_retry" })[0]
  if (-not $retryStep -or $retryStep.reason -ne "codex_transport_eof") { throw "Expected retry reason codex_transport_eof." }
  $task = Invoke-SkyBridgeJson "GET" "/v1/tasks/transport-retry-task"
  if ($task.task.status -ne "completed") { throw "Expected completed task after retry." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    RetryCount = $executeStep.retry_count
    RetryReason = $retryStep.reason
    TaskStatus = $task.task.status
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item Env:SKYBRIDGE_FAKE_CODEX_MARKER -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
