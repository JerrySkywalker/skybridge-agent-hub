param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runner = Join-Path $repoRoot "scripts\powershell\yolo-runner.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-runner-test-" + [Guid]::NewGuid().ToString("N"))

function New-TestQueue {
  $queue = @{
    Root = Join-Path $testRoot ([Guid]::NewGuid().ToString("N"))
  }
  $queue.Ready = Join-Path $queue.Root "goals\ready"
  $queue.Doing = Join-Path $queue.Root "goals\doing"
  $queue.Done = Join-Path $queue.Root "goals\done"
  $queue.Failed = Join-Path $queue.Root "goals\failed"
  $queue.Runs = Join-Path $queue.Root ".agent\runs"
  New-Item -ItemType Directory -Force -Path $queue.Ready,$queue.Doing,$queue.Done,$queue.Failed,$queue.Runs | Out-Null
  return $queue
}

function Write-TestJson {
  param(
    [Parameter(Mandatory=$true)]$Value,
    [Parameter(Mandatory=$true)][string]$Path
  )

  $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding utf8
}

function Invoke-RunnerDryRun {
  param(
    [hashtable]$Queue,
    [int]$LockStaleMinutes = 240,
    [hashtable]$Config = $null
  )

  $configFile = Join-Path $Queue.Root "missing-runner-config.json"
  if ($null -ne $Config) {
    $configFile = Join-Path $Queue.Root "runner-config.json"
    Write-TestJson -Value $Config -Path $configFile
  }

  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner `
    -DryRun `
    -ConfigFile $configFile `
    -GoalsReady $Queue.Ready `
    -GoalsDoing $Queue.Doing `
    -GoalsDone $Queue.Done `
    -GoalsFailed $Queue.Failed `
    -RunRoot $Queue.Runs `
    -LockStaleMinutes $LockStaleMinutes 2>&1

  return @{
    ExitCode = $LASTEXITCODE
    Output = ($output -join [Environment]::NewLine)
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Assert-ExitCode {
  param(
    [hashtable]$Result,
    [int]$Expected,
    [string]$Message
  )

  if ($Result.ExitCode -ne $Expected) {
    throw "$Message`nExit code: $($Result.ExitCode)`nOutput:`n$($Result.Output)"
  }
}

try {
  $queue = New-TestQueue
  $goal = Join-Path $queue.Ready "101-ready-goal.md"
  "# Goal 101`n" | Set-Content -Path $goal -Encoding utf8

  $result = Invoke-RunnerDryRun -Queue $queue
  Assert-ExitCode -Result $result -Expected 0 -Message "Ready dry-run should succeed."
  Assert-True (Test-Path $goal) "Ready dry-run should return the goal to goals/ready."
  Assert-True (-not (Test-Path (Join-Path $queue.Doing "101-ready-goal.md.claim.json"))) "Ready dry-run should remove the temporary claim."
  Assert-True (-not (Test-Path (Join-Path $queue.Doing "101-ready-goal.md.lock.json"))) "Ready dry-run should remove the temporary lock."

  $queue = New-TestQueue
  $doingGoal = Join-Path $queue.Doing "102-resume-goal.md"
  "# Goal 102`n" | Set-Content -Path $doingGoal -Encoding utf8
  Write-TestJson -Value @{
    schema = "skybridge.runner.claim.v1"
    goalId = "102"
    goalFile = "102-resume-goal.md"
    branch = "ai/102-resume-goal"
    runDir = (Join-Path $queue.Runs "resume-102")
    maxParallel = 1
  } -Path (Join-Path $queue.Doing "102-resume-goal.md.claim.json")

  $result = Invoke-RunnerDryRun -Queue $queue
  Assert-ExitCode -Result $result -Expected 0 -Message "Resume dry-run should succeed without an existing lock."
  Assert-True ($result.Output -match "resume=True") "Resume dry-run should report resume mode."
  Assert-True (Test-Path $doingGoal) "Resume dry-run should leave the doing goal in place."
  Assert-True (-not (Test-Path (Join-Path $queue.Doing "102-resume-goal.md.lock.json"))) "Resume dry-run should not create a lock."

  $queue = New-TestQueue
  $staleGoal = Join-Path $queue.Doing "103-stale-goal.md"
  "# Goal 103`n" | Set-Content -Path $staleGoal -Encoding utf8
  Write-TestJson -Value @{
    schema = "skybridge.runner.claim.v1"
    goalId = "103"
    goalFile = "103-stale-goal.md"
    branch = "ai/103-stale-goal"
    runDir = (Join-Path $queue.Runs "resume-103")
    maxParallel = 1
  } -Path (Join-Path $queue.Doing "103-stale-goal.md.claim.json")
  $staleLock = Join-Path $queue.Doing "103-stale-goal.md.lock.json"
  Write-TestJson -Value @{
    schema = "skybridge.runner.lock.v1"
    goalFile = "103-stale-goal.md"
    branch = "ai/103-stale-goal"
    runDir = (Join-Path $queue.Runs "resume-103")
    createdAt = "2000-01-01T00:00:00.0000000Z"
    updatedAt = "2000-01-01T00:00:00.0000000Z"
    host = $env:COMPUTERNAME
    pid = 999999
  } -Path $staleLock

  $result = Invoke-RunnerDryRun -Queue $queue
  Assert-ExitCode -Result $result -Expected 0 -Message "Stale-lock dry-run should be recoverable."
  Assert-True ($result.Output -match "stale lock") "Stale-lock dry-run should report the stale lock."
  Assert-True (Test-Path $staleLock) "Stale-lock dry-run should not archive or remove the lock."

  $queue = New-TestQueue
  $telemetryGoal = Join-Path $queue.Ready "105-telemetry-goal.md"
  "# Goal 105`n" | Set-Content -Path $telemetryGoal -Encoding utf8

  $result = Invoke-RunnerDryRun -Queue $queue -Config @{
    telemetry = @{
      enabled = $true
      apiBase = "http://127.0.0.1:9"
      timeoutSeconds = 1
    }
  }
  Assert-ExitCode -Result $result -Expected 0 -Message "Telemetry dry-run should succeed even when the server is offline."
  Assert-True (Test-Path $telemetryGoal) "Telemetry dry-run should return the goal to goals/ready."

  $queue = New-TestQueue
  $mismatchGoal = Join-Path $queue.Doing "104-mismatch-goal.md"
  "# Goal 104`n" | Set-Content -Path $mismatchGoal -Encoding utf8
  Write-TestJson -Value @{
    schema = "skybridge.runner.claim.v1"
    goalId = "104"
    goalFile = "104-mismatch-goal.md"
    branch = "ai/999-wrong-goal"
    runDir = (Join-Path $queue.Runs "resume-104")
    maxParallel = 1
  } -Path (Join-Path $queue.Doing "104-mismatch-goal.md.claim.json")

  $result = Invoke-RunnerDryRun -Queue $queue
  Assert-True ($result.ExitCode -ne 0) "Branch mismatch dry-run should fail."
  Assert-True ($result.Output -match "does not match expected branch") "Branch mismatch should explain the expected branch."

  Write-Host "[test-yolo-runner] all runner dry-run tests passed"
} finally {
  if (Test-Path $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
