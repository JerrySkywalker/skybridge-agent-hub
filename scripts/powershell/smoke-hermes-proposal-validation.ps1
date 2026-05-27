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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-proposal-validation-" + [Guid]::NewGuid().ToString("n"))
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
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-validation"; name = "Hermes Validation" } | Out-Null
  $safe = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 -ApiBase $apiBase -ProjectId hermes-validation -MasterGoalId hermes-validation-goal -Title "Hermes safe validation" -PlannerMode hermes-preview -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-safe.json -DryRun -Json | ConvertFrom-Json
  $unsafe = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 -ApiBase $apiBase -ProjectId hermes-validation -MasterGoalId hermes-validation-unsafe -Title "Hermes unsafe validation" -PlannerMode hermes-preview -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-unsafe.json -DryRun -Json | ConvertFrom-Json
  if (@($safe.proposals | Where-Object { $_.policy_decision -eq "accepted_for_preview" }).Count -lt 1) { throw "Expected at least one safe accepted proposal." }
  if (@($unsafe.proposals | Where-Object { $_.policy_decision -in @("rejected_high_risk", "rejected_expected_files", "ask_human") }).Count -lt 1) { throw "Expected unsafe proposal rejection." }
  $summary = @{ ok = $true; safe = @($safe.proposals)[0].policy_decision; unsafe = @($unsafe.proposals)[0].policy_decision; token_printed = $false }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
