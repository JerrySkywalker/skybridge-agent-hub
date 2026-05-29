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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-capability-normalization-" + [Guid]::NewGuid().ToString("n"))
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
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-capabilities"; name = "Hermes Capability Normalization" } | Out-Null
  $preview = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-capabilities `
    -MasterGoalId hermes-capabilities-goal `
    -Title "Hermes capability normalization smoke" `
    -PlannerMode hermes-preview `
    -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-normalization.json `
    -DryRun `
    -Json | ConvertFrom-Json

  $docs = @($preview.proposals | Where-Object { $_.dedupe_key -eq "sprint-progress-checkpoint" })[0]
  $smoke = @($preview.proposals | Where-Object { $_.dedupe_key -eq "worker-readiness-smoke" })[0]
  $deploy = @($preview.proposals | Where-Object { $_.dedupe_key -eq "deploy-hermes-proxy" })[0]

  if (@($docs.original_required_capabilities) -notcontains "git") { throw "Expected docs original capabilities to include git." }
  if (@($docs.normalized_required_capabilities) -notcontains "codex") { throw "Expected docs normalized capabilities to include codex." }
  if (@($smoke.original_required_capabilities) -notcontains "powershell") { throw "Expected smoke original capabilities to include powershell." }
  if (@($smoke.normalized_required_capabilities) -notcontains "codex") { throw "Expected smoke normalized capabilities to include codex." }
  if ($docs.policy_decision -ne "accepted_for_preview") { throw "Expected docs proposal to pass policy." }
  if ($smoke.policy_decision -ne "accepted_for_preview") { throw "Expected smoke proposal to pass policy." }
  if ($deploy.policy_decision -eq "accepted_for_preview") { throw "Unsafe deploy proposal must not pass policy." }

  $summary = [pscustomobject]@{
    ok = $true
    docs_original_required_capabilities = @($docs.original_required_capabilities)
    docs_normalized_required_capabilities = @($docs.normalized_required_capabilities)
    smoke_original_required_capabilities = @($smoke.original_required_capabilities)
    smoke_normalized_required_capabilities = @($smoke.normalized_required_capabilities)
    deploy_policy_decision = $deploy.policy_decision
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
