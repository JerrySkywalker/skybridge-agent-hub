$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$script:WorkerTemplateRunnerServerProcess = $null
$script:WorkerTemplateRunnerTempDir = $null
$script:WorkerTemplateRunnerApiBase = $null

function Invoke-WorkerTemplateRunnerJson {
  param(
    [string]$Method,
    [string]$Path,
    $Body = $null
  )
  $uri = "$script:WorkerTemplateRunnerApiBase$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Wait-WorkerTemplateRunnerServer {
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    try { return Invoke-WorkerTemplateRunnerJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 400 }
  }
  throw "Worker template runner smoke server did not become healthy."
}

function Start-WorkerTemplateRunnerSmokeServer {
  $script:WorkerTemplateRunnerTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-template-runner-" + [Guid]::NewGuid().ToString("n"))
  New-Item -ItemType Directory -Path $script:WorkerTemplateRunnerTempDir | Out-Null
  $dbFile = Join-Path $script:WorkerTemplateRunnerTempDir "skybridge.sqlite"
  $port = Get-Random -Minimum 28001 -Maximum 38000
  $script:WorkerTemplateRunnerApiBase = "http://127.0.0.1:$port"
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REQUIRE_WORKER_AUTH -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $script:WorkerTemplateRunnerServerProcess = Start-Process @startProcessParams
  Wait-WorkerTemplateRunnerServer | Out-Null
  $script:WorkerTemplateRunnerApiBase
}

function Stop-WorkerTemplateRunnerSmokeServer {
  if ($script:WorkerTemplateRunnerServerProcess) {
    try { $script:WorkerTemplateRunnerServerProcess.Kill($true) } catch { Stop-Process -Id $script:WorkerTemplateRunnerServerProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if ($script:WorkerTemplateRunnerTempDir) {
    Remove-Item -LiteralPath $script:WorkerTemplateRunnerTempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-WorkerTemplateRunnerScript {
  param(
    [string]$Command,
    [string]$ProjectId = "skybridge-agent-hub",
    [string]$WorkerId = "mg329-worker-template-runner",
    [string]$TaskId = "",
    [string]$TemplateId = "",
    [int]$MaxTasks = 1,
    [switch]$Confirm,
    [string]$ConfirmationText = ""
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-worker-template-runner.ps1"
  $scriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $scriptPath,
    "-Command",
    $Command,
    "-ApiBase",
    $script:WorkerTemplateRunnerApiBase,
    "-ProjectId",
    $ProjectId,
    "-WorkerId",
    $WorkerId,
    "-MaxTasks",
    $MaxTasks,
    "-Json"
  )
  if (-not [string]::IsNullOrWhiteSpace($TaskId)) { $scriptArgs += @("-TaskId", $TaskId) }
  if (-not [string]::IsNullOrWhiteSpace($TemplateId)) { $scriptArgs += @("-TemplateId", $TemplateId) }
  if ($Confirm) { $scriptArgs += "-Confirm" }
  if (-not [string]::IsNullOrWhiteSpace($ConfirmationText)) { $scriptArgs += @("-ConfirmationText", $ConfirmationText) }
  $raw = & pwsh @scriptArgs
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Assert-RunnerForbiddenFlagsFalse {
  param($Value, [string]$Name)
  Assert-False $Value.pr_created "$Name pr_created"
  Assert-False $Value.codex_run_called "$Name codex_run_called"
  Assert-False $Value.matlab_run_called "$Name matlab_run_called"
  Assert-False $Value.arbitrary_shell_enabled "$Name arbitrary_shell_enabled"
  Assert-False $Value.worker_loop_started "$Name worker_loop_started"
  Assert-False $Value.unbounded_run_enabled "$Name unbounded_run_enabled"
  Assert-False $Value.project_control_unpaused "$Name project_control_unpaused"
  Assert-TokenPrintedFalse $Value
}

function Assert-RunnerNoClaimOrExecution {
  param($Value, [string]$Name)
  Assert-False $Value.claim_created "$Name claim_created"
  Assert-False $Value.execution_started "$Name execution_started"
  Assert-False $Value.execution_completed "$Name execution_completed"
  Assert-False $Value.execution_failed "$Name execution_failed"
  Assert-RunnerForbiddenFlagsFalse $Value $Name
}

function Seed-WorkerTemplateRunnerFixture {
  param(
    [string]$ProjectId = "skybridge-agent-hub",
    [string]$TaskId = "mg329-safe-local-smoke-fixture"
  )
  $seed = Invoke-WorkerTemplateRunnerScript -Command "fixture-seed-safe-task" -ProjectId $ProjectId -TaskId $TaskId
  if ([string]$seed.schema -ne "skybridge.worker_template_runner_fixture_seed.v1") { throw "Unexpected fixture seed schema." }
  if ($seed.ok -ne $true) { throw "Fixture seed failed." }
  Assert-False $seed.claim_created "fixture seed claim_created"
  Assert-False $seed.execution_started "fixture seed execution_started"
  Assert-False $seed.codex_run_called "fixture seed codex_run_called"
  Assert-False $seed.matlab_run_called "fixture seed matlab_run_called"
  Assert-False $seed.arbitrary_shell_enabled "fixture seed arbitrary_shell_enabled"
  Assert-False $seed.worker_loop_started "fixture seed worker_loop_started"
  Assert-False $seed.unbounded_run_enabled "fixture seed unbounded_run_enabled"
  Assert-False $seed.project_control_unpaused "fixture seed project_control_unpaused"
  Assert-TokenPrintedFalse $seed
  $seed
}
