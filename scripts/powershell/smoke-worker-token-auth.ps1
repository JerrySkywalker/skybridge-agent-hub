param(
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

$fixtureToken = "fixture-worker-token-165"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null, [string]$Token = "") {
  $uri = "$ApiBase$Path"
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers["Authorization"] = "Bearer $Token" }
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-token-auth-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-token-auth.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; `$env:SKYBRIDGE_WORKER_TOKEN = '$fixtureToken'; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  $registered = Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{
    worker_id = "token-worker"
    name = "Token worker"
    provider = "edge-worker"
    capabilities = @("docs")
  } $fixtureToken
  if ($registered.worker.worker_id -ne "token-worker") { throw "Expected token-worker registration." }

  $heartbeat = Invoke-SkyBridgeJson "POST" "/v1/workers/token-worker/heartbeat" @{
    status_note = "ready"
  } $fixtureToken
  if ($heartbeat.worker.status -ne "online") { throw "Expected token worker to heartbeat online." }

  $localServerCommand = "`$env:SKYBRIDGE_DB_FILE = '$(Join-Path $tempDir "local-noauth.sqlite")'; `$env:PORT = '$($Port + 1)'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $localProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $localServerCommand); PassThru = $true }
  if ($IsWindows) { $localProcessParams.WindowStyle = "Hidden" }
  $localProcess = Start-Process @localProcessParams
  try {
    $oldApiBase = $ApiBase
    $ApiBase = "http://127.0.0.1:$($Port + 1)"
    Wait-SkyBridgeHealth | Out-Null
    $local = Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{
      worker_id = "local-noauth-worker"
      name = "Local no-auth worker"
    }
    if ($local.worker.worker_id -ne "local-noauth-worker") { throw "Expected local no-auth worker registration." }
  } finally {
    $ApiBase = $oldApiBase
    try { $localProcess.Kill($true) } catch { Stop-Process -Id $localProcess.Id -Force -ErrorAction SilentlyContinue }
  }

  $result = [pscustomobject]@{
    ApiBase = $ApiBase
    CorrectTokenAllowed = $true
    LocalDevNoAuthAllowed = $true
    TokenPrinted = $false
  }
  $text = ($result | ConvertTo-Json -Depth 8)
  if ($text -match [regex]::Escape($fixtureToken)) { throw "Smoke output included token value." }
  $result | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
