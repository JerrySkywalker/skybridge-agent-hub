param(
  [string]$FixtureDirectory = ".\packages\agent-adapters\codex-hook\src\fixtures",
  [string]$ApiBase = "http://127.0.0.1:1",
  [string]$SpoolDirectory,
  [switch]$RequireSpool
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SpoolDirectory)) {
  $SpoolDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-codex-hook-test-" + [guid]::NewGuid().ToString("n"))
}

New-Item -ItemType Directory -Force -Path $SpoolDirectory | Out-Null
$fixtures = @(Get-ChildItem -Path $FixtureDirectory -Filter "*.json" -File | Sort-Object Name)
if ($fixtures.Count -eq 0) { throw "No fixture JSON files found in $FixtureDirectory" }

foreach ($fixture in $fixtures) {
  Get-Content -Raw -Path $fixture.FullName | & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\codex-dashboard-hook.ps1 -ApiBase $ApiBase -SpoolDirectory $SpoolDirectory
  if ($LASTEXITCODE -ne 0) { throw "Hook failed for fixture $($fixture.Name)" }
}

$auditFile = Join-Path $SpoolDirectory "events.jsonl"
$queueFile = Join-Path $SpoolDirectory "queue.jsonl"
$auditLines = if (Test-Path $auditFile) { @(Get-Content -Path $auditFile | Where-Object { $_ }) } else { @() }
$queueLines = if (Test-Path $queueFile) { @(Get-Content -Path $queueFile | Where-Object { $_ }) } else { @() }
if ($auditLines.Count -lt $fixtures.Count) { throw "Expected at least $($fixtures.Count) normalized audit events, found $($auditLines.Count)" }
if ($RequireSpool -and $queueLines.Count -lt $fixtures.Count) { throw "Expected offline queue entries, found $($queueLines.Count)" }

$combined = ($auditLines -join "`n")
if ($combined -match 'secret-token|hunter2|sk-test-secret|OPENAI_API_KEY=secret|abc123') { throw "Unsafe fixture secret leaked into hook output" }

Write-Output (@{
  ok = $true
  fixtureCount = $fixtures.Count
  normalizedEventCount = $auditLines.Count
  queuedEventCount = $queueLines.Count
  spoolDirectory = $SpoolDirectory
} | ConvertTo-Json -Compress)
