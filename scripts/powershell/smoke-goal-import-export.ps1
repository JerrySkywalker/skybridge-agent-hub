param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal-import-export-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-goal-import-export.sqlite"
$goalFile = Join-Path $tempDir "goal.md"
$exportFile = Join-Path $tempDir "goal-export.md"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "goal-import-project"; name = "Goal Import Project" } | Out-Null
  @"
# Imported Goal

goal_id: imported-goal
status: ready
source: smoke-import
priority: high
risk: low
dedupe_key: smoke/imported-goal

## Summary
Validate Markdown import and export.

## Acceptance Criteria
- Imported goal keeps acceptance.
- Exported goal includes evidence requirements.

## Evidence Requirements
- Smoke script output.
"@ | Set-Content -LiteralPath $goalFile -Encoding UTF8

  $import = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\import-goal-markdown.ps1 -GoalFile $goalFile -ApiBase $ApiBase -ProjectId "goal-import-project" -Json | ConvertFrom-Json
  if ($import.goal.goal_id -ne "imported-goal") { throw "Expected imported-goal." }
  if (@($import.goal.acceptance_criteria).Count -ne 2) { throw "Expected imported acceptance criteria." }

  $export = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\export-goal-markdown.ps1 -GoalId "imported-goal" -ApiBase $ApiBase -OutFile $exportFile -Json | ConvertFrom-Json
  if (-not $export.ok -or -not (Test-Path -LiteralPath $exportFile -PathType Leaf)) { throw "Expected exported Markdown." }
  $exportedText = Get-Content -Raw -LiteralPath $exportFile
  if ($exportedText -notmatch "Imported goal keeps acceptance" -or $exportedText -notmatch "Smoke script output") {
    throw "Exported Markdown did not preserve acceptance/evidence fields."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    ImportedGoal = $import.goal.goal_id
    ExportFile = $exportFile
    SecretsIncluded = $false
    CodexExecuted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
