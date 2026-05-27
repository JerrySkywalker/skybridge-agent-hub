[CmdletBinding()]
param([switch]$DryRun, [switch]$Json)

$ErrorActionPreference = "Stop"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-eval-" + [Guid]::NewGuid().ToString("n"))
$dbFile = Join-Path $tempDir "skybridge.sqlite"
$port = Get-Random -Minimum 18000 -Maximum 28000
$apiBase = "http://127.0.0.1:$port"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$server = $null
try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $server = Start-Process @startProcessParams
  $healthy = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try {
      Invoke-RestMethod "$apiBase/v1/health" | Out-Null
      $healthy = $true
      break
    } catch { Start-Sleep -Milliseconds 500 }
  }
  if (-not $healthy) { throw "SkyBridge server did not become healthy at $apiBase." }
  Invoke-RestMethod -Method Post -Uri "$apiBase/v1/projects" -ContentType "application/json" -Body (@{ project_id = "eval-project"; name = "Eval project" } | ConvertTo-Json) | Out-Null
  Invoke-RestMethod -Method Post -Uri "$apiBase/v1/tasks" -ContentType "application/json" -Body (@{ task_id = "eval-task"; project_id = "eval-project"; title = "Eval task"; source = "hermes-planner"; risk = "low" } | ConvertTo-Json) | Out-Null
  Invoke-RestMethod -Method Post -Uri "$apiBase/v1/tasks/eval-task/complete" -ContentType "application/json" -Body (@{ summary = "done" } | ConvertTo-Json) | Out-Null
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-hermes-evaluate-result.ps1" -TaskId "eval-task" -ApiBase $apiBase -DryRun -Json
  if ($LASTEXITCODE -ne 0) { throw "Hermes evaluate dry-run failed." }
  $result = $output | ConvertFrom-Json
  if ($result.hermes_recommendation -ne "continue") { throw "Expected continue evaluation." }
  if ($result.final_decision -ne "skybridge_policy_required") { throw "Expected SkyBridge policy to remain final." }
  $summary = @{ ok = $true; recommendation = $result.hermes_recommendation; final_decision = $result.final_decision; dry_run = $true }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { Write-Host "[smoke-hermes-evaluate-result] ok=$($summary.ok) recommendation=$($summary.recommendation)" }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
