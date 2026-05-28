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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-preview-wrapper-" + [Guid]::NewGuid().ToString("n"))
$dbFile = Join-Path $tempDir "skybridge.sqlite"
$constraintsFile = Join-Path $tempDir "constraints.json"
$outputFile = Join-Path $tempDir "preview.json"
$summaryFile = Join-Path $tempDir "summary.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$apiBase = "http://127.0.0.1:$Port"
$server = $null
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
@("Constraint one", "Constraint two", "Constraint three") | ConvertTo-Json | Set-Content -LiteralPath $constraintsFile -Encoding UTF8
try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $server = Start-Process @startProcessParams
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; break } catch { Start-Sleep -Milliseconds 500 }
    if ($attempt -eq 39) { throw "SkyBridge server did not become healthy." }
  }
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-preview-wrapper"; name = "Hermes Preview Wrapper" } | Out-Null
  $result = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-preview.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-preview-wrapper `
    -MasterGoalId hermes-preview-wrapper-goal `
    -Title "Hermes preview wrapper smoke" `
    -Description "Validate wrapper behavior." `
    -ConstraintsFile $constraintsFile `
    -PlannerFixtureFile .\scripts\powershell\fixtures\hermes-proposals-safe.json `
    -HealthFixtureFile .\scripts\powershell\fixtures\hermes-capabilities.json `
    -HermesApiBase https://hermes-api.example.invalid `
    -OutputFile $outputFile `
    -SummaryOutputFile $summaryFile `
    -Json | ConvertFrom-Json

  if ($result.mode -ne "dry-run") { throw "Expected dry-run mode." }
  if ($result.summary.planner_mode -ne "hermes-preview") { throw "Expected hermes-preview." }
  if ($result.summary.proposal_count -lt 1) { throw "Expected proposals." }
  if ($result.summary.token_printed -ne $false) { throw "Expected token_printed=false." }
  if (-not (Test-Path -LiteralPath $outputFile)) { throw "Expected output file." }
  if (-not (Test-Path -LiteralPath $summaryFile)) { throw "Expected summary file." }
  if (@($result.plan.master_goal.constraints).Count -ne 3) { throw "Expected three constraints." }

  $summary = [pscustomobject]@{
    ok = $true
    proposal_count = $result.summary.proposal_count
    accepted_for_preview_count = $result.summary.accepted_for_preview_count
    constraints = @($result.plan.master_goal.constraints).Count
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
