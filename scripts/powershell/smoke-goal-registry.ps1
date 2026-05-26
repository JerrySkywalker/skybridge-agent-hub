param(
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -eq "POST" -or $Method -eq "PATCH") {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Invoke-ExpectFailure([scriptblock]$Script, [string]$Label) {
  try {
    & $Script | Out-Null
  } catch {
    return
  }
  throw "Expected failure: $Label"
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal-registry-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-goal-registry.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "registry-project"; name = "Registry Project" } | Out-Null
  $created = Invoke-SkyBridgeJson "POST" "/v1/projects/registry-project/goals" @{
    goal_id = "goal-registry-smoke"
    title = "Harden goal registry smoke"
    source = "smoke"
    priority = "high"
    risk = "medium"
    lifecycle = "ready"
    acceptance_criteria = @("metadata persisted", "governance enforced")
    evidence_requirements = @("task evidence summary")
    dedupe_key = "smoke-goal-registry"
    planner_metadata = @{ adapter = "fixture"; plan_id = "smoke-plan" }
    model_backend_metadata = @{ provider = "fixture"; model = "fixture-model"; secret = "must-not-persist" }
  }
  if ($created.goal.priority -ne "high") { throw "Expected priority to persist." }
  if ($created.goal.risk -ne "medium") { throw "Expected risk to persist." }
  if ($created.goal.model_backend_metadata.secret) { throw "Model backend metadata must not persist arbitrary secret fields." }

  Invoke-ExpectFailure {
    Invoke-SkyBridgeJson "PATCH" "/v1/goals/goal-registry-smoke" @{ status = "blocked" }
  } "blocked goal requires reason"

  Invoke-SkyBridgeJson "POST" "/v1/projects/registry-project/goals" @{
    goal_id = "goal-registry-replacement"
    title = "Replacement goal"
    source = "smoke"
  } | Out-Null
  $superseded = Invoke-SkyBridgeJson "PATCH" "/v1/goals/goal-registry-smoke" @{
    status = "superseded"
    superseded_by = "goal-registry-replacement"
  }
  if ($superseded.goal.status -ne "superseded") { throw "Expected superseded status." }
  if ($superseded.goal.superseded_by -ne "goal-registry-replacement") { throw "Expected superseded_by link." }

  $completed = Invoke-SkyBridgeJson "PATCH" "/v1/goals/goal-registry-replacement" @{
    status = "completed"
    completion_note = "Smoke completion note."
  }
  if ($completed.goal.status -ne "completed") { throw "Expected completed replacement goal." }

  $list = Invoke-SkyBridgeJson "GET" "/v1/projects/registry-project/goals"
  if (@($list.goals).Count -lt 2) { throw "Expected two goals in registry project." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Goals = @($list.goals).Count
    SupersededGoal = $superseded.goal.goal_id
    ReplacementStatus = $completed.goal.status
    Governance = "passed"
    NoRealCredentials = $true
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
