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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-proposal-conversion-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-proposal-conversion.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "convert-project"; name = "Convert Project" } | Out-Null
  $plan = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 -ApiBase $ApiBase -ProjectId convert-project -MasterGoalId convert-master -Title "Convert smoke goal" -Apply -Json | ConvertFrom-Json
  $proposalId = @($plan.proposals)[0].proposal_id

  $approve = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command approve -ApiBase $ApiBase -ProjectId convert-project -ProposalId $proposalId -Apply -Reason "conversion smoke approval" -Json | ConvertFrom-Json
  $preview = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command convert -ApiBase $ApiBase -ProjectId convert-project -ProposalId $proposalId -TaskId converted-task -DryRun -Json | ConvertFrom-Json
  $convert = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command convert -ApiBase $ApiBase -ProjectId convert-project -ProposalId $proposalId -TaskId converted-task -Apply -Json | ConvertFrom-Json

  if ($preview.task.task_id -ne "converted-task" -or @($preview.task.required_capabilities).Count -lt 1) { throw "Expected conversion preview task shape." }
  if ($approve.proposal.status -ne "approved") { throw "Expected approved proposal before conversion." }
  if ($convert.proposal.status -ne "converted" -or $convert.task.task_id -ne "converted-task") { throw "Expected converted proposal/task." }
  if (@($convert.task.allowed_paths).Count -lt 1) { throw "Expected converted task allowed paths from expected files." }
  if ($convert.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Preview = "passed"
    Convert = "passed"
    TaskId = $convert.task.task_id
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
