[CmdletBinding()]
param([int]$Port = 0, [switch]$Json)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$apiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-supervisor-preview-" + [Guid]::NewGuid().ToString("n"))
$dbFile = Join-Path $tempDir "skybridge.sqlite"
$outputDir = Join-Path $tempDir "out"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$apiBase = "http://127.0.0.1:$Port"
$server = $null
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $server = Start-Process @startProcessParams
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; break } catch { Start-Sleep -Milliseconds 500 }
    if ($attempt -eq 39) { throw "SkyBridge server did not become healthy." }
  }
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-supervisor-preview"; name = "Hermes Supervisor Preview" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "preview-worker"; name = "Preview Worker"; capabilities = @("codex") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/preview-worker/heartbeat" @{ status_note = "fixture" } | Out-Null
  $result = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervise.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-supervisor-preview `
    -MasterGoalId hermes-supervisor-preview-goal `
    -GoalTitle "Hermes supervisor preview smoke" `
    -PlannerMode hermes-preview `
    -PlannerFixtureFile .\scripts\powershell\fixtures\hermes-proposals-safe.json `
    -DryRun `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  if ($result.supervisor_run.max_rounds -ne 2) { throw "Expected default MaxRounds=2." }
  if ($result.supervisor_run.status -ne "completed") { throw "Expected completed preview." }
  if (@($result.rounds)[0].hermes_advisory.final_decision -ne @($result.rounds)[0].decision.decision) { throw "Expected deterministic policy final decision." }
  $summary = @{ ok = $true; max_rounds = $result.supervisor_run.max_rounds; selected = @($result.rounds)[0].selected_proposal_id; token_printed = $false }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
