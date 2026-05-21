param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$FixtureDirectory = ".\packages\agent-adapters\codex-hook\src\fixtures",
  [string]$SpoolDirectory,
  [switch]$StartServer,
  [int]$ServerStartupSeconds = 20
)

$ErrorActionPreference = "Stop"

function Test-ServerHealth {
  param([string]$Base)
  try {
    $health = Invoke-RestMethod -Method Get -Uri "$Base/health" -TimeoutSec 2
    return [bool]$health.ok
  } catch {
    return $false
  }
}

function Wait-ServerHealth {
  param([string]$Base, [int]$Seconds)
  for ($i = 0; $i -lt $Seconds; $i++) {
    if (Test-ServerHealth -Base $Base) { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
}

function Invoke-FixturesThroughHook {
  param([string]$Directory, [string]$Base, [string]$Spool)
  $fixtures = @(Get-ChildItem -Path $Directory -Filter "*.json" -File | Sort-Object Name)
  if ($fixtures.Count -eq 0) { throw "No fixture JSON files found in $Directory" }
  foreach ($fixture in $fixtures) {
    Get-Content -Raw -Path $fixture.FullName | & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\codex-dashboard-hook.ps1 -ApiBase $Base -SpoolDirectory $Spool
    if ($LASTEXITCODE -ne 0) { throw "Hook failed for fixture $($fixture.Name)" }
  }
  return $fixtures.Count
}

function Assert-NoSecretLeak {
  param([object[]]$Events)
  $text = $Events | ConvertTo-Json -Depth 80 -Compress
  if ($text -match 'secret-token|hunter2|sk-test-secret|OPENAI_API_KEY=secret|abc123') {
    throw "Unsafe fixture secret leaked into persisted events."
  }
}

if ([string]::IsNullOrWhiteSpace($SpoolDirectory)) {
  $SpoolDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-codex-smoke-" + [guid]::NewGuid().ToString("n"))
}
New-Item -ItemType Directory -Force -Path $SpoolDirectory | Out-Null

$serverProcess = $null
if (-not (Test-ServerHealth -Base $ApiBase)) {
  if (-not $StartServer) { throw "SkyBridge server is not healthy at $ApiBase. Start it or pass -StartServer." }
  $uri = [uri]$ApiBase
  $port = $uri.Port
  $hostName = if ([string]::IsNullOrWhiteSpace($uri.Host)) { "127.0.0.1" } else { $uri.Host }
  $dbFile = Join-Path $SpoolDirectory "smoke-skybridge.sqlite"
  $command = "`$env:PORT='$port'; `$env:HOST='$hostName'; `$env:SKYBRIDGE_DB_FILE='$dbFile'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $serverProcess = Start-Process -FilePath "pwsh" -ArgumentList @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command) -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -PassThru
  if (-not (Wait-ServerHealth -Base $ApiBase -Seconds $ServerStartupSeconds)) { throw "Started server did not become healthy at $ApiBase" }
}

try {
  $fixtureCount = Invoke-FixturesThroughHook -Directory $FixtureDirectory -Base $ApiBase -Spool $SpoolDirectory
  Start-Sleep -Milliseconds 300

  $eventsResponse = Invoke-RestMethod -Method Get -Uri "$ApiBase/v1/events?source_platform=codex&source_adapter=codex-hook&limit=200" -TimeoutSec 5
  $events = @($eventsResponse.events)
  if ($events.Count -lt $fixtureCount) { throw "Expected at least $fixtureCount Codex hook events, found $($events.Count)" }
  Assert-NoSecretLeak -Events $events
  if (-not ($events | Where-Object { $_.type -eq "approval.requested" })) { throw "Expected approval.requested event from fixtures." }
  if (-not ($events | Where-Object { $_.type -eq "tool.failed" })) { throw "Expected tool.failed event from fixtures." }

  $runsResponse = Invoke-RestMethod -Method Get -Uri "$ApiBase/v1/runs" -TimeoutSec 5
  $codexRuns = @($runsResponse.runs | Where-Object { $_.source_platform -eq "codex" -and $_.source_adapter -eq "codex-hook" })
  if ($codexRuns.Count -eq 0) { throw "Expected at least one Codex run summary." }
  if (-not ($codexRuns | Where-Object { $_.tool_call_count -gt 0 })) { throw "Expected Codex run summary to reflect tool events." }

  $offlineDir = Join-Path $SpoolDirectory "offline"
  New-Item -ItemType Directory -Force -Path $offlineDir | Out-Null
  $offlineFixtureCount = Invoke-FixturesThroughHook -Directory $FixtureDirectory -Base "http://127.0.0.1:1" -Spool $offlineDir
  $queueFile = Join-Path $offlineDir "queue.jsonl"
  $queued = if (Test-Path $queueFile) { @(Get-Content -Path $queueFile | Where-Object { $_ }) } else { @() }
  if ($queued.Count -lt $offlineFixtureCount) { throw "Expected offline queued events, found $($queued.Count)" }

  $replay = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\replay-codex-hook-spool.ps1 -ApiBase $ApiBase -SpoolDirectory $offlineDir | ConvertFrom-Json
  if ($replay.remaining -ne 0 -or $replay.delivered -lt $offlineFixtureCount) { throw "Replay failed: $($replay | ConvertTo-Json -Compress)" }

  Write-Output (@{
    ok = $true
    apiBase = $ApiBase
    fixtureCount = $fixtureCount
    persistedCodexEvents = $events.Count
    codexRunCount = $codexRuns.Count
    offlineQueued = $queued.Count
    replayDelivered = $replay.delivered
    spoolDirectory = $SpoolDirectory
  } | ConvertTo-Json -Compress)
} finally {
  if ($serverProcess -and -not $serverProcess.HasExited) {
    Stop-Process -Id $serverProcess.Id -Force
  }
}
