param(
  [int]$Port = 0
)

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

function Invoke-EdgeWorkerJson([string]$ConfigPath) {
  $output = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
    -ConfigFile $ConfigPath `
    -Register `
    -Heartbeat `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-edge-worker.ps1 failed for $ConfigPath." }
  $jsonLines = @($output | Where-Object { $_ -match "^\s*\{" })
  if ($jsonLines.Count -lt 1) { throw "Expected JSON output from edge worker." }
  return ($jsonLines[-1] | ConvertFrom-Json)
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-edge-worker-profile-normalization-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-edge-worker-profile-normalization.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"
$repoPath = (Resolve-Path ".").Path
$profilePath = Join-Path $tempDir "worker-profile.json"
$legacyPath = Join-Path $tempDir "edge-worker-legacy.json"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  @{
    worker_id = "profile-normalized-worker"
    display_name = "Profile normalized worker"
    project_ids = @("skybridge-agent-hub")
    repo_paths = @{ "skybridge-agent-hub" = $repoPath }
    capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
    executor_adapters = @("codex")
    preferred_task_types = @("docs", "code", "test")
    blocked_task_types = @("deploy", "secrets", "production")
    max_parallel_tasks = 1
    allow_auto_merge = $false
    allow_production_deploy = $false
    allow_remote_server = $false
    reject_insecure_http_for_remote = $true
    skybridge_api_base = $ApiBase
    auth_mode = "none"
    token_env_var = "SKYBRIDGE_WORKER_TOKEN"
    codex_command = "codex"
    codex_sandbox = "workspace-write"
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $profilePath -Encoding UTF8

  $profileResult = Invoke-EdgeWorkerJson -ConfigPath $profilePath
  if (-not $profileResult.ok) { throw "Expected new-format profile edge worker result to be ok." }
  $profileSteps = @($profileResult.steps | ForEach-Object { $_.step })
  if ($profileSteps -notcontains "register" -or $profileSteps -notcontains "heartbeat") {
    throw "Expected register and heartbeat steps for new-format profile."
  }
  $profileWorker = Invoke-SkyBridgeJson "GET" "/v1/workers/profile-normalized-worker"
  if ($profileWorker.worker.status -ne "online") { throw "Expected normalized profile worker to be online." }

  @{
    worker_id = "legacy-runtime-worker"
    name = "Legacy runtime worker"
    project_id = "skybridge-agent-hub"
    repo_path = $repoPath
    api_base = $ApiBase
    capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
    allowed_task_types = @("docs", "code", "test")
    blocked_task_types = @("deploy", "secrets", "production")
    codex_command = "codex"
    codex_sandbox = "workspace-write"
    auto_merge_enabled = $false
    notification_enabled = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $legacyPath -Encoding UTF8

  $legacyResult = Invoke-EdgeWorkerJson -ConfigPath $legacyPath
  if (-not $legacyResult.ok) { throw "Expected legacy runtime config edge worker result to be ok." }
  $legacyWorker = Invoke-SkyBridgeJson "GET" "/v1/workers/legacy-runtime-worker"
  if ($legacyWorker.worker.status -ne "online") { throw "Expected legacy worker to be online." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    NewFormatProfileDirect = $true
    LegacyRuntimeConfig = $true
    TokenPrinted = $false
    ProfileWorkerStatus = $profileWorker.worker.status
    LegacyWorkerStatus = $legacyWorker.worker.status
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
