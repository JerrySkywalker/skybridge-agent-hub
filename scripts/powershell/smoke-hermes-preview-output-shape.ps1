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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-output-shape-" + [Guid]::NewGuid().ToString("n"))
$dbFile = Join-Path $tempDir "skybridge.sqlite"
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
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-output-shape"; name = "Hermes Output Shape" } | Out-Null
  $preview = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-output-shape `
    -MasterGoalId hermes-output-shape-goal `
    -Title "Hermes output shape smoke" `
    -PlannerMode hermes-preview `
    -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-safe.json `
    -DryRun `
    -Json | ConvertFrom-Json

  if (@($preview.proposals).Count -le 0) { throw "Expected top-level proposals." }
  if (@($preview.planning_session.proposals).Count -le 0) { throw "Expected planning_session.proposals." }
  if (@($preview.proposals).Count -ne @($preview.planning_session.proposals).Count) { throw "Expected matching proposal counts." }
  for ($i = 0; $i -lt @($preview.proposals).Count; $i++) {
    if ($preview.proposals[$i].proposal_id -ne $preview.planning_session.proposals[$i].proposal_id) { throw "Expected matching proposal id." }
    if ([string]::IsNullOrWhiteSpace([string]$preview.proposals[$i].policy_decision)) { throw "Expected policy decision." }
    if ($preview.proposals[$i].policy_decision -ne $preview.planning_session.proposals[$i].policy_decision) { throw "Expected matching policy decision." }
  }

  $summary = [pscustomobject]@{
    ok = $true
    proposal_count = @($preview.proposals).Count
    planning_session_proposal_count = @($preview.planning_session.proposals).Count
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
