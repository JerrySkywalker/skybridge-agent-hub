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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-master-planner-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-master-planner.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "planner-project"; name = "Planner Project" } | Out-Null

  $dryRun = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $ApiBase `
    -ProjectId planner-project `
    -MasterGoalId master-planner-goal `
    -Title "Master planner smoke goal" `
    -Description "Create safe task proposals." `
    -DryRun `
    -Json | ConvertFrom-Json
  if ($dryRun.mode -ne "dry-run" -or @($dryRun.proposals).Count -lt 1) { throw "Expected planner dry-run proposals." }

  $apply = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $ApiBase `
    -ProjectId planner-project `
    -MasterGoalId master-planner-goal `
    -Title "Master planner smoke goal" `
    -Description "Create safe task proposals." `
    -Apply `
    -Json | ConvertFrom-Json
  if ($apply.mode -ne "apply" -or $apply.master_goal_action -notin @("created", "existing") -or @($apply.proposals).Count -lt 1) {
    throw "Expected planner apply to create master goal and proposals."
  }
  $stored = Invoke-SkyBridgeJson "GET" "/v1/master-goals/master-planner-goal/proposals"
  if (@($stored.proposals).Count -lt 1) { throw "Expected stored proposals." }
  if ($apply.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    DryRun = "passed"
    Apply = "passed"
    ProposalCount = @($stored.proposals).Count
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
