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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-constraints-" + [Guid]::NewGuid().ToString("n"))
$dbFile = Join-Path $tempDir "skybridge.sqlite"
$constraintsFile = Join-Path $tempDir "constraints.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$apiBase = "http://127.0.0.1:$Port"
$server = $null
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
@("first constraint", "second constraint", "third constraint") | ConvertTo-Json | Set-Content -LiteralPath $constraintsFile -Encoding UTF8
try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $server = Start-Process @startProcessParams
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; break } catch { Start-Sleep -Milliseconds 500 }
    if ($attempt -eq 39) { throw "SkyBridge server did not become healthy." }
  }
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-constraints"; name = "Hermes Constraints" } | Out-Null
  $preview = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-constraints `
    -MasterGoalId hermes-constraints-goal `
    -Title "Hermes constraints smoke" `
    -PlannerMode hermes-preview `
    -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-safe.json `
    -ConstraintsFile $constraintsFile `
    -DryRun `
    -Json | ConvertFrom-Json

  if (@($preview.master_goal.constraints).Count -ne 3) { throw "Expected three constraints." }
  if (@($preview.master_goal.acceptance_criteria).Count -ne 1) { throw "Expected default acceptance criteria only." }
  if ($preview.master_goal.acceptance_criteria[0] -ne "Task proposals are reviewed before executable tasks are created.") { throw "Expected default acceptance criteria unchanged." }
  if (@($preview.master_goal.stop_conditions).Count -ne 1) { throw "Expected default stop condition only." }
  if ($preview.master_goal.stop_conditions[0] -ne "Stop before any high-risk or production deployment work.") { throw "Expected default stop condition unchanged." }

  $summary = [pscustomobject]@{
    ok = $true
    constraints = @($preview.master_goal.constraints).Count
    acceptance_criteria = @($preview.master_goal.acceptance_criteria).Count
    stop_conditions = @($preview.master_goal.stop_conditions).Count
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
