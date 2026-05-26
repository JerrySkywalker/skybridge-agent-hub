param(
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

$fixtureToken = "fixture-worker-token-165"

function Invoke-WorkerRequest([string]$Token) {
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers["Authorization"] = "Bearer $Token" }
  Invoke-RestMethod -Method POST -Uri "$ApiBase/v1/workers/register" -Headers $headers -ContentType "application/json" -Body (@{
    worker_id = "failure-worker"
    name = "Failure worker"
  } | ConvertTo-Json -Depth 8)
}

function Expect-Failure([scriptblock]$Script, [string]$ExpectedError) {
  try {
    & $Script | Out-Null
  } catch {
    $message = $_.Exception.Message
    $responseText = [string]$_.ErrorDetails.Message
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = [System.IO.StreamReader]::new($stream)
        $responseText = $reader.ReadToEnd()
      }
    } catch {}
    $combined = "$message $responseText"
    if ($combined -notmatch $ExpectedError) {
      throw "Expected failure containing '$ExpectedError', got '$message $responseText'."
    }
    if ($combined -match [regex]::Escape($fixtureToken)) {
      throw "Failure response leaked token value."
    }
    return
  }
  throw "Expected request to fail with $ExpectedError."
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-RestMethod "$ApiBase/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-token-auth-failure-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-token-auth-failure.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; `$env:SKYBRIDGE_WORKER_TOKEN = '$fixtureToken'; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Expect-Failure { Invoke-WorkerRequest "" } "missing_worker_token"
  Expect-Failure { Invoke-WorkerRequest "wrong-token" } "invalid_worker_token"
  Expect-Failure {
    Invoke-RestMethod -Method POST -Uri "$ApiBase/v1/tasks/example-task/claim" -ContentType "application/json" -Body (@{
      worker_id = "failure-worker"
    } | ConvertTo-Json -Depth 8)
  } "missing_worker_token"

  [pscustomobject]@{
    ApiBase = $ApiBase
    MissingTokenRejected = $true
    WrongTokenRejected = $true
    ProtectedTaskRouteRejected = $true
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
