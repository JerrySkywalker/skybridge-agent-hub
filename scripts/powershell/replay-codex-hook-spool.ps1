param(
  [string]$ApiBase = $env:SKYBRIDGE_API_BASE,
  [string]$SpoolDirectory = $env:SKYBRIDGE_CODEX_SPOOL_DIR,
  [int]$TimeoutSeconds = 5,
  [switch]$WhatIfOnly
)

$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
  $current = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  while ($true) {
    if (Test-Path (Join-Path $current "pnpm-workspace.yaml")) { return $current }
    $parent = Split-Path -Parent $current
    if ($parent -eq $current) { return (Get-Location).Path }
    $current = $parent
  }
}

if ([string]::IsNullOrWhiteSpace($ApiBase)) { $ApiBase = "http://127.0.0.1:8787" }
if ([string]::IsNullOrWhiteSpace($SpoolDirectory)) { $SpoolDirectory = Join-Path (Get-RepositoryRoot) ".agent\spool\codex-hook" }

$queueFile = Join-Path $SpoolDirectory "queue.jsonl"
$archiveFile = Join-Path $SpoolDirectory "delivered.jsonl"
if (-not (Test-Path $queueFile)) {
  Write-Output "No Codex hook spool queue found at $queueFile"
  exit 0
}

$lines = @(Get-Content -Path $queueFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$remaining = New-Object System.Collections.Generic.List[string]
$delivered = 0
$failed = 0

foreach ($line in $lines) {
  if ($WhatIfOnly) {
    $remaining.Add($line)
    continue
  }
  try {
    $headers = @{}
    if ($env:CODEX_DASHBOARD_TOKEN) { $headers["Authorization"] = "Bearer $($env:CODEX_DASHBOARD_TOKEN)" }
    Invoke-RestMethod -Method Post -Uri "$ApiBase/v1/events" -ContentType "application/json" -Headers $headers -Body $line -TimeoutSec $TimeoutSeconds | Out-Null
    New-Item -ItemType Directory -Force -Path $SpoolDirectory | Out-Null
    Add-Content -Path $archiveFile -Value $line -Encoding UTF8
    $delivered += 1
  } catch {
    $remaining.Add($line)
    $failed += 1
  }
}

if (-not $WhatIfOnly) {
  if ($remaining.Count -gt 0) {
    $remaining | Set-Content -Path $queueFile -Encoding UTF8
  } else {
    Remove-Item -LiteralPath $queueFile -Force
  }
}

Write-Output (@{
  ok = ($failed -eq 0)
  apiBase = $ApiBase
  spoolDirectory = $SpoolDirectory
  queued = $lines.Count
  delivered = $delivered
  remaining = $remaining.Count
  whatIfOnly = [bool]$WhatIfOnly
} | ConvertTo-Json -Compress)
