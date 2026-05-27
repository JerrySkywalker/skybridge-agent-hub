param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-guide-supervisor-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-guide-supervisor.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "guide-supervisor-project"; name = "Guide Supervisor Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "guide-supervisor-worker"; name = "Guide Supervisor Worker"; capabilities = @("codex") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/guide-supervisor-worker/heartbeat" @{ status_note = "fixture" } | Out-Null

  $preview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
    -Mode supervise-preview `
    -ApiBase $ApiBase `
    -ProjectId guide-supervisor-project `
    -MasterGoalId guide-supervisor-master `
    -GoalTitle "Guide supervisor smoke goal" `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  $status = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
    -Mode supervise-status `
    -ApiBase $ApiBase `
    -ProjectId guide-supervisor-project `
    -MasterGoalId guide-supervisor-master `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json

  if ($preview.mode -ne "supervise-preview" -or $preview.supervise.supervisor_run.mode -ne "dry-run") { throw "Expected guide supervise-preview dry run." }
  if ($preview.next_command -notmatch "supervise-apply") { throw "Expected next supervise-apply command." }
  if ($status.mode -ne "supervise-status" -or $status.token_printed -ne $false) { throw "Expected guide supervise-status." }
  if ($preview.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Preview = "passed"
    Status = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
