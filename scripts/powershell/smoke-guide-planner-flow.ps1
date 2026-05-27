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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-guide-planner-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-guide-planner.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "guide-plan-project"; name = "Guide Planner Project" } | Out-Null

  $preview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode plan-preview -ApiBase $ApiBase -ProjectId guide-plan-project -MasterGoalId guide-master -GoalTitle "Guide planner smoke goal" -DryRun -OutputDir $outputDir -Json | ConvertFrom-Json
  $apply = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode plan-apply -ApiBase $ApiBase -ProjectId guide-plan-project -MasterGoalId guide-master -GoalTitle "Guide planner smoke goal" -Apply -OutputDir $outputDir -Json | ConvertFrom-Json
  $list = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode proposals -ApiBase $ApiBase -ProjectId guide-plan-project -MasterGoalId guide-master -OutputDir $outputDir -Json | ConvertFrom-Json
  $proposalId = @($list.proposals.proposals)[0].proposal_id
  $convertPreview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 -Mode proposal-convert-preview -ApiBase $ApiBase -ProjectId guide-plan-project -ProposalId $proposalId -TaskId guide-converted-task -OutputDir $outputDir -Json | ConvertFrom-Json

  if ($preview.plan.mode -ne "dry-run" -or @($preview.plan.proposals).Count -lt 1) { throw "Expected guide plan-preview." }
  if ($apply.plan.mode -ne "apply" -or @($apply.plan.proposals).Count -lt 1) { throw "Expected guide plan-apply." }
  if (@($list.proposals.proposals).Count -lt 1) { throw "Expected guide proposals list." }
  if ($convertPreview.task.task_id -ne "guide-converted-task") { throw "Expected guide proposal convert preview." }
  if ($convertPreview.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    PlanPreview = "passed"
    PlanApply = "passed"
    Proposals = "passed"
    ConvertPreview = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
