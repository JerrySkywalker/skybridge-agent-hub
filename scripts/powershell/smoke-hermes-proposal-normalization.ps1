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

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-normalization-" + [Guid]::NewGuid().ToString("n"))
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
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "hermes-normalization"; name = "Hermes Normalization" } | Out-Null
  $preview = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
    -ApiBase $apiBase `
    -ProjectId hermes-normalization `
    -MasterGoalId hermes-normalization-goal `
    -Title "Hermes proposal normalization smoke" `
    -PlannerMode hermes-preview `
    -FixtureFile .\scripts\powershell\fixtures\hermes-proposals-normalization.json `
    -DryRun `
    -Json | ConvertFrom-Json

  $smoke = @($preview.proposals | Where-Object { $_.dedupe_key -eq "worker-readiness-smoke" })[0]
  $docs = @($preview.proposals | Where-Object { $_.dedupe_key -eq "sprint-progress-checkpoint" })[0]
  $deploy = @($preview.proposals | Where-Object { $_.dedupe_key -eq "deploy-hermes-proxy" })[0]
  $unsafeTest = @($preview.proposals | Where-Object { $_.dedupe_key -eq "unsafe-test-file" })[0]

  if ($smoke.task_type -ne "local-smoke" -or $smoke.original_task_type -ne "smoke") { throw "Expected smoke to normalize to local-smoke." }
  if ($docs.task_type -ne "docs") { throw "Expected docs to remain docs." }
  if (@($smoke.original_required_capabilities) -notcontains "powershell" -or @($smoke.original_required_capabilities) -notcontains "windows") { throw "Expected original smoke capabilities to be preserved." }
  if (@($smoke.normalized_required_capabilities) -notcontains "codex" -or @($smoke.normalized_required_capabilities) -notcontains "powershell" -or @($smoke.normalized_required_capabilities) -notcontains "windows") { throw "Expected smoke capabilities to add codex and keep powershell/windows." }
  if (@($docs.original_required_capabilities) -notcontains "git" -or @($docs.original_required_capabilities) -notcontains "docs") { throw "Expected original docs capabilities to be preserved." }
  if (@($docs.normalized_required_capabilities) -notcontains "codex") { throw "Expected docs capabilities to add codex." }
  if ($smoke.policy_decision -ne "accepted_for_preview") { throw "Expected normalized smoke to pass preview policy." }
  if ($docs.policy_decision -ne "accepted_for_preview") { throw "Expected normalized docs to pass preview policy." }
  if ($deploy.policy_decision -notin @("ask_human", "rejected_high_risk")) { throw "Expected deploy to be blocked for human review." }
  if ($unsafeTest.policy_decision -notin @("ask_human", "rejected_expected_files")) { throw "Expected unsafe expected_files to be rejected or ask_human." }

  $summary = [pscustomobject]@{
    ok = $true
    smoke_task_type = $smoke.task_type
    smoke_original_task_type = $smoke.original_task_type
    smoke_capabilities = @($smoke.normalized_required_capabilities)
    docs_task_type = $docs.task_type
    docs_capabilities = @($docs.normalized_required_capabilities)
    deploy_decision = $deploy.policy_decision
    unsafe_test_decision = $unsafeTest.policy_decision
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
