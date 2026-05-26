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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal-task-evidence-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-goal-task-evidence.sqlite"
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

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "evidence-project"; name = "Evidence Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects/evidence-project/goals" @{
    goal_id = "evidence-goal"
    title = "Evidence goal"
    status = "active"
    acceptance_criteria = @("task evidence recorded")
    evidence_requirements = @("summary plus validation status")
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "evidence-worker"; name = "Evidence worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/evidence-worker/heartbeat" @{} | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "evidence-task"
    project_id = "evidence-project"
    goal_id = "evidence-goal"
    title = "Complete evidence task"
    risk = "low"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/evidence-task/claim" @{ worker_id = "evidence-worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/evidence-task/complete" @{
    summary = "Evidence task completed without real Codex."
    evidence_summary = @{
      task_id = "evidence-task"
      goal_id = "evidence-goal"
      pr_url = "https://github.com/example/repo/pull/1"
      commit_sha = "abcdef1234567890"
      changed_files = @("docs/example.md")
      validation_status = "passed"
      ci_status = "not_run"
      risk_status = "low"
      summary = "Fixture evidence recorded."
    }
  } | Out-Null

  $goal = Invoke-SkyBridgeJson "GET" "/v1/goals/evidence-goal"
  if ($goal.goal.status -ne "partially_completed") { throw "Expected active goal to become partially_completed after task evidence." }
  if ($goal.goal.task_summary.completed -ne 1) { throw "Expected completed task count on goal detail." }
  if ($goal.goal.progress_summary.evidence_count -ne 1) { throw "Expected evidence_count to update." }
  if ($goal.goal.evidence_summary.validation_status -ne "passed") { throw "Expected goal evidence summary validation status." }

  Invoke-SkyBridgeJson "POST" "/v1/projects/evidence-project/goals" @{
    goal_id = "archived-goal"
    title = "Archived goal"
    status = "archived"
  } | Out-Null
  Invoke-ExpectFailure {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
      task_id = "archived-task"
      project_id = "evidence-project"
      goal_id = "archived-goal"
      title = "Should not execute"
    }
  } "archived goal cannot receive executable task"

  [pscustomobject]@{
    ApiBase = $ApiBase
    GoalStatus = $goal.goal.status
    CompletedTasks = $goal.goal.task_summary.completed
    EvidenceCount = $goal.goal.progress_summary.evidence_count
    ValidationStatus = $goal.goal.evidence_summary.validation_status
    ArchivedGoalGuard = "passed"
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
