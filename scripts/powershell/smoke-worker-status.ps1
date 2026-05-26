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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-status-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-status.sqlite"
$profileFile = Join-Path $tempDir "worker.status.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "worker-status-project"; name = "Worker Status Project" } | Out-Null

  @{
    worker_id = "worker-status-smoke"
    display_name = "Worker Status Smoke"
    project_ids = @("worker-status-project")
    allowed_project_ids = @("worker-status-project")
    repo_paths = @{ "worker-status-project" = (Resolve-Path ".").Path }
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

  $result = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-status.ps1 -Command register-heartbeat -ConfigFile $profileFile -ProjectId worker-status-project -Json | ConvertFrom-Json
  $text = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-status.ps1 -Command status -ConfigFile $profileFile -ProjectId worker-status-project
  if ($result.worker_id -ne "worker-status-smoke") { throw "Expected worker id." }
  if ($result.registered -ne $true -or $result.heartbeat -ne $true) { throw "Expected register and heartbeat success." }
  if ($result.remote_status -ne "online") { throw "Expected online worker." }
  if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }
  if (($text -join "`n") -notmatch "TokenPrinted: false") { throw "Expected compact token marker." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    RegisterHeartbeat = "passed"
    Status = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
