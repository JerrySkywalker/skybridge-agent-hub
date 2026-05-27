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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-task-proposals-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-task-proposals.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "proposal-project"; name = "Proposal Project" } | Out-Null
  pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 -ApiBase $ApiBase -ProjectId proposal-project -MasterGoalId proposal-master -Title "Proposal smoke goal" -Apply -Json | Out-Null

  $list = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command list -ApiBase $ApiBase -ProjectId proposal-project -MasterGoalId proposal-master -Json | ConvertFrom-Json
  $proposalId = @($list.proposals)[0].proposal_id
  $show = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command show -ApiBase $ApiBase -ProjectId proposal-project -ProposalId $proposalId -Json | ConvertFrom-Json
  $acceptDryRun = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command accept -ApiBase $ApiBase -ProjectId proposal-project -ProposalId $proposalId -DryRun -Json | ConvertFrom-Json
  $accept = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -Command accept -ApiBase $ApiBase -ProjectId proposal-project -ProposalId $proposalId -Apply -Json | ConvertFrom-Json

  if (@($list.proposals).Count -lt 1) { throw "Expected proposals." }
  if ($show.proposal.proposal_id -ne $proposalId) { throw "Expected proposal show." }
  if ($acceptDryRun.proposal.status -ne "would_accept") { throw "Expected accept dry-run." }
  if ($accept.proposal.status -ne "accepted") { throw "Expected accepted proposal." }
  if ($list.token_printed -ne $false -or $accept.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    List = "passed"
    Show = "passed"
    AcceptDryRun = "passed"
    AcceptApply = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
