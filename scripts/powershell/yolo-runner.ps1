param(
  [ValidateSet("ThesisYOLO", "Conservative")]
  [string]$Mode = "ThesisYOLO",

  [int]$MaxRepairRounds = 3,

  [int]$MaxParallel = 1,

  [switch]$AutoPR,

  [switch]$AutoMergeLowRisk,

  [switch]$NotifyOnlyImportant = $true,

  [string]$GoalsReady = ".\goals\ready",

  [string]$GoalsDoing = ".\goals\doing",

  [string]$GoalsDone = ".\goals\done",

  [string]$GoalsFailed = ".\goals\failed",

  [string]$RunRoot = ".\.agent\runs",

  [string]$ConfigFile = ".\config\runner.json",

  [string]$CodexCommand = "codex",

  [switch]$Loop,

  [int]$PollSeconds = 60,

  [int]$LockStaleMinutes = 240,

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "shared-redaction.ps1")

$script:RunnerTelemetry = @{
  Enabled = $false
}
$script:RunnerRedactionRules = Get-SkyBridgeSharedRedactionRules

function ConvertTo-PlainObject {
  param([Parameter(Position=0, ValueFromPipeline=$true)]$Value)

  process {
    if ($null -eq $Value) {
      return $null
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
      $hash = @{}
      foreach ($property in $Value.PSObject.Properties) {
        $hash[$property.Name] = ConvertTo-PlainObject $property.Value
      }
      return $hash
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
      $items = @()
      foreach ($item in $Value) {
        $items += ConvertTo-PlainObject $item
      }
      return $items
    }

    return $Value
  }
}

function Import-RunnerConfig {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @{}
  }

  $config = Get-Content $Path -Raw | ConvertFrom-Json
  return ConvertTo-PlainObject $config
}

function Get-ConfigValue {
  param(
    [hashtable]$Config,
    [string]$Name,
    $Default
  )

  if ($Config.ContainsKey($Name) -and $null -ne $Config[$Name]) {
    return $Config[$Name]
  }

  return $Default
}

function ConvertTo-Boolean {
  param(
    $Value,
    [bool]$Default = $false
  )

  if ($null -eq $Value) {
    return $Default
  }

  if ($Value -is [bool]) {
    return $Value
  }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $Default
  }

  return $text -in @("1", "true", "yes", "on")
}

function Initialize-RunnerTelemetry {
  param([hashtable]$Config)

  $telemetryConfig = @{}
  if ($Config.ContainsKey("telemetry") -and $Config["telemetry"] -is [hashtable]) {
    $telemetryConfig = $Config["telemetry"]
  }

  $enabled = ConvertTo-Boolean `
    -Value (Get-ConfigValue $telemetryConfig "enabled" $env:SKYBRIDGE_RUNNER_TELEMETRY) `
    -Default $false
  $apiBase = [string](Get-ConfigValue $telemetryConfig "apiBase" $env:SKYBRIDGE_API_BASE)
  if ([string]::IsNullOrWhiteSpace($apiBase)) {
    $apiBase = "http://127.0.0.1:8787"
  }

  $timeoutSeconds = [int](Get-ConfigValue $telemetryConfig "timeoutSeconds" 3)
  $tokenEnvironmentVariable = [string](Get-ConfigValue $telemetryConfig "tokenEnvironmentVariable" "SKYBRIDGE_API_TOKEN")
  $agentId = [string](Get-ConfigValue $telemetryConfig "agentId" "skybridge-yolo-runner")
  $nodeId = [string](Get-ConfigValue $telemetryConfig "nodeId" $env:SKYBRIDGE_NODE_ID)
  if ([string]::IsNullOrWhiteSpace($nodeId)) {
    $nodeId = $env:COMPUTERNAME
  }

  $script:RunnerTelemetry = @{
    Enabled = $enabled
    ApiBase = $apiBase.TrimEnd("/")
    TimeoutSeconds = $timeoutSeconds
    TokenEnvironmentVariable = $tokenEnvironmentVariable
    AgentId = $agentId
    NodeId = $nodeId
  }
  $script:RunnerRedactionRules = Get-SkyBridgeSharedRedactionRules
}

function ConvertTo-RunnerTelemetryPayload {
  param([hashtable]$Payload = @{})

  $safePayload = ConvertTo-SkyBridgeSafeValue -Value $Payload -Rules $script:RunnerRedactionRules
  if ($safePayload -isnot [hashtable]) {
    $safePayload = @{
      value = $safePayload
    }
  }

  if (-not $safePayload.ContainsKey("redaction_policy")) {
    $safePayload["redaction_policy"] = @{
      source = $script:RunnerRedactionRules.source
      max_string_length = $script:RunnerRedactionRules.maxStringLength
    }
  }

  return $safePayload
}

function New-RunnerEvent {
  param(
    [Parameter(Mandatory=$true)][string]$Type,
    [ValidateSet("debug", "info", "warning", "error", "critical")]
    [string]$Severity = "info",
    [hashtable]$Correlation = @{},
    [hashtable]$Payload = @{}
  )

  $safePayload = ConvertTo-RunnerTelemetryPayload -Payload $Payload
  $safeCorrelation = ConvertTo-SkyBridgeSafeValue -Value $Correlation -Rules $script:RunnerRedactionRules

  return @{
    schema = "skybridge.agent_event.v1"
    event_id = "evt_runner_$([Guid]::NewGuid().ToString("N"))"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $Type
    severity = $Severity
    source = @{
      platform = "skybridge"
      adapter = "yolo-runner"
      node_id = Redact-SkyBridgeString -Value $script:RunnerTelemetry.NodeId -Rules $script:RunnerRedactionRules -MaxLength 160
      agent_id = Redact-SkyBridgeString -Value $script:RunnerTelemetry.AgentId -Rules $script:RunnerRedactionRules -MaxLength 160
      cwd = Redact-SkyBridgeString -Value (Get-Location).Path -Rules $script:RunnerRedactionRules -MaxLength 240
    }
    correlation = $safeCorrelation
    payload = $safePayload
  }
}

function Send-RunnerEvent {
  param(
    [Parameter(Mandatory=$true)][string]$Type,
    [ValidateSet("debug", "info", "warning", "error", "critical")]
    [string]$Severity = "info",
    [hashtable]$Correlation = @{},
    [hashtable]$Payload = @{}
  )

  if (-not $script:RunnerTelemetry.Enabled) {
    return
  }

  $event = New-RunnerEvent -Type $Type -Severity $Severity -Correlation $Correlation -Payload $Payload
  $body = $event | ConvertTo-Json -Depth 80 -Compress
  $headers = @{}
  $tokenName = [string]$script:RunnerTelemetry.TokenEnvironmentVariable
  if (-not [string]::IsNullOrWhiteSpace($tokenName)) {
    $token = [Environment]::GetEnvironmentVariable($tokenName)
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $headers["Authorization"] = "Bearer $token"
    }
  }

  try {
    Invoke-RestMethod `
      -Method Post `
      -Uri "$($script:RunnerTelemetry.ApiBase)/v1/events" `
      -ContentType "application/json" `
      -Headers $headers `
      -Body $body `
      -TimeoutSec $script:RunnerTelemetry.TimeoutSeconds | Out-Null
  } catch {
    Write-Verbose "[yolo-runner] SkyBridge telemetry delivery failed: $($_.Exception.Message)"
  }
}

function Get-RunnerCorrelation {
  param(
    [hashtable]$GoalParts = @{},
    [string]$RunDir = $null
  )

  $runId = $null
  if ($GoalParts.ContainsKey("Base")) {
    $runId = "runner-$($GoalParts.Base)"
  }

  if ([string]::IsNullOrWhiteSpace($runId) -and -not [string]::IsNullOrWhiteSpace($RunDir)) {
    $runId = "runner-$([IO.Path]::GetFileName($RunDir))"
  }

  return @{
    session_id = "runner-$PID"
    run_id = $runId
  }
}

function Resolve-CommandPath {
  param([string]$Name)
  return (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-GoalParts {
  param([string]$FileName)

  $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
  if ($base -match "^(?<id>\d+)[-_](?<slug>.+)$") {
    return @{
      Id = $Matches["id"]
      Slug = ($Matches["slug"] -replace "[^A-Za-z0-9._-]+", "-").Trim("-").ToLowerInvariant()
      Base = $base
    }
  }

  return @{
    Id = $base
    Slug = ($base -replace "[^A-Za-z0-9._-]+", "-").Trim("-").ToLowerInvariant()
    Base = $base
  }
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory=$true)]$Value,
    [Parameter(Mandatory=$true)][string]$Path
  )

  $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding utf8
}

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  return ConvertTo-PlainObject (Get-Content $Path -Raw | ConvertFrom-Json)
}

function Get-UniquePath {
  param([Parameter(Mandatory=$true)][string]$Path)

  if (-not (Test-Path $Path)) {
    return $Path
  }

  $directory = Split-Path $Path -Parent
  $leaf = Split-Path $Path -Leaf
  $extension = [IO.Path]::GetExtension($leaf)
  $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $candidate = Join-Path $directory ("{0}.{1}{2}" -f $stem, $timestamp, $extension)
  $index = 1

  while (Test-Path $candidate) {
    $candidate = Join-Path $directory ("{0}.{1}.{2}{3}" -f $stem, $timestamp, $index, $extension)
    $index += 1
  }

  return $candidate
}

function Invoke-LoggedNativeCommand {
  param(
    [Parameter(Mandatory=$true)][string]$LogFile,
    [Parameter(Mandatory=$true)][string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$CommandArgs
  )

  $output = & $Command @CommandArgs 2>&1
  $exitCode = $LASTEXITCODE
  $output | Tee-Object -FilePath $LogFile | ForEach-Object { Write-Host $_ }
  return $exitCode
}

function Send-AgentNotice {
  param(
    [string]$Title,
    [string]$Message,
    [ValidateSet("min", "low", "default", "high", "urgent")]
    [string]$Priority = "default",
    [hashtable]$Correlation = @{}
  )

  Send-RunnerEvent `
    -Type "notification.requested" `
    -Severity $(if ($Priority -in @("high", "urgent")) { "warning" } else { "info" }) `
    -Correlation $Correlation `
    -Payload @{
      title = $Title
      priority = $Priority
      message_length = if ($null -eq $Message) { 0 } else { $Message.Length }
      message_omitted = $true
      redaction = "notification message body omitted by default"
    }

  if ($NotifyOnlyImportant -and $Priority -in @("min", "low", "default")) {
    Write-Host "[$Title] $Message"
    return
  }

  $notify = ".\scripts\powershell\notify-ntfy.ps1"
  if (Test-Path $notify) {
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $notify -Title $Title -Message $Message -Priority $Priority
  } else {
    Write-Host "[$Title] $Message"
  }
}

function Invoke-StandardCheck {
  param([string]$RunDir, [int]$Attempt)

  $just = Resolve-CommandPath "just"
  $logFile = Join-Path $RunDir ("check-{0}.log" -f $Attempt)

  if ($just) {
    Write-Host "[yolo-runner] running just check"
    return Invoke-LoggedNativeCommand -LogFile $logFile -Command "just" -CommandArgs @("check")
  }

  Write-Host "[yolo-runner] running corepack pnpm check"
  return Invoke-LoggedNativeCommand -LogFile $logFile -Command "corepack" -CommandArgs @("pnpm", "check")
}

function Invoke-CodexJson {
  param(
    [string]$RunDir,
    [string]$JsonlName,
    [string]$LastMessageName,
    [string]$Prompt,
    [string]$Sandbox
  )

  $jsonl = Join-Path $RunDir $JsonlName
  $lastMessage = Join-Path $RunDir $LastMessageName

  Write-Host "[yolo-runner] codex exec -> $jsonl"

  if ($Sandbox -eq "dangerously-bypass-approvals-and-sandbox") {
    & $CodexCommand exec `
      --dangerously-bypass-approvals-and-sandbox `
      --json `
      --output-last-message $lastMessage `
      $Prompt 2>&1 | Tee-Object -FilePath $jsonl | ForEach-Object { Write-Host $_ }
  } else {
    & $CodexCommand exec `
      --sandbox $Sandbox `
      --ask-for-approval never `
      --json `
      --output-last-message $lastMessage `
      $Prompt 2>&1 | Tee-Object -FilePath $jsonl | ForEach-Object { Write-Host $_ }
  }

  return $LASTEXITCODE
}

function Get-BranchForGoal {
  param([hashtable]$GoalParts)
  return "ai/$($GoalParts.Id)-$($GoalParts.Slug)"
}

function Get-GoalLockPath {
  param([string]$ClaimPath)
  return ($ClaimPath -replace "\.claim\.json$", ".lock.json")
}

function Test-ProcessAlive {
  param([int]$ProcessId)

  if ($ProcessId -le 0) {
    return $false
  }

  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-GoalLockState {
  param(
    [string]$LockPath,
    [int]$StaleMinutes
  )

  $lock = Read-JsonFile $LockPath
  if ($null -eq $lock) {
    return @{
      Status = "missing"
      Lock = $null
      Reason = "No lock file exists."
    }
  }

  $now = (Get-Date).ToUniversalTime()
  $updatedAt = $null
  if ($lock.ContainsKey("updatedAt")) {
    $updatedAt = [DateTime]::Parse($lock["updatedAt"]).ToUniversalTime()
  } elseif ($lock.ContainsKey("createdAt")) {
    $updatedAt = [DateTime]::Parse($lock["createdAt"]).ToUniversalTime()
  }

  $ageMinutes = 0
  if ($null -ne $updatedAt) {
    $ageMinutes = ($now - $updatedAt).TotalMinutes
  }

  $sameHost = $lock.ContainsKey("host") -and $lock["host"] -eq $env:COMPUTERNAME
  $processAlive = $false
  if ($sameHost -and $lock.ContainsKey("pid")) {
    $processAlive = Test-ProcessAlive ([int]$lock["pid"])
  }

  if ($sameHost -and -not $processAlive) {
    return @{
      Status = "stale"
      Lock = $lock
      Reason = "Lock process $($lock["pid"]) is not running on $env:COMPUTERNAME."
    }
  }

  if ($ageMinutes -gt $StaleMinutes) {
    return @{
      Status = "stale"
      Lock = $lock
      Reason = "Lock age $([Math]::Round($ageMinutes, 1)) minutes exceeds stale threshold $StaleMinutes minutes."
    }
  }

  return @{
    Status = "active"
    Lock = $lock
    Reason = "Lock is active."
  }
}

function New-GoalLock {
  param(
    [string]$GoalFile,
    [string]$Branch,
    [string]$RunDir,
    [string]$LockPath,
    [string]$Reason
  )

  $now = (Get-Date).ToUniversalTime().ToString("o")
  $lock = @{
    schema = "skybridge.runner.lock.v1"
    goalFile = $GoalFile
    branch = $Branch
    runDir = $RunDir
    createdAt = $now
    updatedAt = $now
    host = $env:COMPUTERNAME
    pid = $PID
    reason = $Reason
  }

  Write-JsonFile -Value $lock -Path $LockPath
  return $lock
}

function Archive-StaleLock {
  param(
    [string]$LockPath,
    [string]$Reason
  )

  if (-not (Test-Path $LockPath)) {
    return
  }

  $archivePath = Get-UniquePath (Join-Path (Split-Path $LockPath -Parent) ("{0}.{1}.stale.json" -f (Split-Path $LockPath -Leaf), (Get-Date -Format "yyyyMMdd-HHmmss")))
  $lock = Read-JsonFile $LockPath
  if ($null -ne $lock) {
    $lock["staleDetectedAt"] = (Get-Date).ToUniversalTime().ToString("o")
    $lock["staleReason"] = $Reason
    Write-JsonFile -Value $lock -Path $archivePath
    Remove-Item $LockPath -Force
    Write-Host "[yolo-runner] archived stale lock $LockPath -> $archivePath"
  }
}

function Switch-ToGoalBranch {
  param([string]$Branch)

  $currentBranch = (git branch --show-current).Trim()
  if ($currentBranch -eq $Branch) {
    Write-Host "[yolo-runner] already on branch $Branch"
    return
  }

  $existingBranch = git branch --list $Branch
  if ($existingBranch) {
    git checkout $Branch
  } else {
    git checkout -b $Branch
  }
}

function Commit-IfNeeded {
  param(
    [string]$Message,
    [string[]]$Paths = @(".")
  )

  foreach ($path in $Paths) {
    git add -- $path
  }

  $staged = git diff --cached --name-only
  if (-not $staged) {
    Write-Host "[yolo-runner] no staged changes for commit: $Message"
    return $false
  }

  git commit -m $Message
  return $true
}

function Push-Branch {
  param([string]$Branch)

  git push -u origin $Branch
}

function New-PullRequestIfAvailable {
  param(
    [string]$GoalTitle,
    [string]$Branch,
    [string]$RunDir
  )

  $gh = Resolve-CommandPath "gh"
  if (-not $gh) {
    Write-Host "[yolo-runner] gh not found; skipping PR creation."
    return
  }

  $body = @"
Autonomous runner completed goal: $GoalTitle

Run log directory: $RunDir

Checklist:
- [x] Codex exec run completed
- [x] Standard check passed locally
- [x] Branch pushed
"@

  gh pr create --fill --head $Branch --label ai-generated --label yolo --body $body
}

function Complete-GoalState {
  param(
    [string]$DoingPath,
    [string]$ClaimPath,
    [string]$TargetDir,
    [string]$LockPath
  )

  $targetGoal = Get-UniquePath (Join-Path $TargetDir (Split-Path $DoingPath -Leaf))
  Move-Item $DoingPath $targetGoal -Force

  if (Test-Path $ClaimPath) {
    $targetClaim = Get-UniquePath (Join-Path $TargetDir (Split-Path $ClaimPath -Leaf))
    Move-Item $ClaimPath $targetClaim
  }

  if ($LockPath -and (Test-Path $LockPath)) {
    $targetLock = Get-UniquePath (Join-Path $TargetDir (Split-Path $LockPath -Leaf))
    Move-Item $LockPath $targetLock
  }

  return $targetGoal
}

function Assert-GoalClaimMatches {
  param(
    [hashtable]$GoalParts,
    [string]$GoalFile,
    [string]$ExpectedBranch,
    [hashtable]$Claim
  )

  if ($null -eq $Claim) {
    throw "Cannot resume $GoalFile because its claim file is missing."
  }

  if ($Claim.ContainsKey("goalFile") -and $Claim["goalFile"] -ne $GoalFile) {
    throw "Claim goalFile '$($Claim["goalFile"])' does not match goal '$GoalFile'."
  }

  if ($Claim.ContainsKey("goalId") -and $Claim["goalId"] -ne $GoalParts.Id) {
    throw "Claim goalId '$($Claim["goalId"])' does not match goal id '$($GoalParts.Id)'."
  }

  if ($Claim.ContainsKey("branch") -and $Claim["branch"] -ne $ExpectedBranch) {
    throw "Claim branch '$($Claim["branch"])' does not match expected branch '$ExpectedBranch'."
  }
}

function Select-GoalWorkItem {
  param(
    [string]$ReadyDir,
    [string]$DoingDir,
    [string]$RunRoot,
    [int]$StaleMinutes,
    [int]$EffectiveMaxParallel,
    [int]$EffectiveMaxRepairRounds,
    [string]$EffectiveMode,
    [bool]$DryRunMode
  )

  $doingGoal = Get-ChildItem $DoingDir -Filter "*.md" | Sort-Object Name | Select-Object -First 1
  if ($doingGoal) {
    $goalParts = Get-GoalParts $doingGoal.Name
    $branch = Get-BranchForGoal $goalParts
    $doingPath = $doingGoal.FullName
    $claimPath = Join-Path $DoingDir ("{0}.claim.json" -f $doingGoal.Name)
    $lockPath = Get-GoalLockPath $claimPath
    $claim = Read-JsonFile $claimPath
    Assert-GoalClaimMatches -GoalParts $goalParts -GoalFile $doingGoal.Name -ExpectedBranch $branch -Claim $claim

    $lockState = Get-GoalLockState -LockPath $lockPath -StaleMinutes $StaleMinutes
    if ($lockState.Status -eq "active") {
      Write-Host "[yolo-runner] goal $($doingGoal.Name) is locked by pid $($lockState.Lock["pid"]) on $($lockState.Lock["host"]); skipping."
      return $null
    }

    if ($lockState.Status -eq "stale") {
      Write-Host "[yolo-runner] resuming $($doingGoal.Name) after stale lock: $($lockState.Reason)"
      if (-not $DryRunMode) {
        Archive-StaleLock -LockPath $lockPath -Reason $lockState.Reason
      }
    } else {
      Write-Host "[yolo-runner] resuming claimed goal $($doingGoal.Name) without an active lock."
    }

    $runDir = [string]$claim["runDir"]
    if (-not $runDir) {
      $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
      $runDir = Join-Path $RunRoot ("{0}-{1}-resume" -f $timestamp, $goalParts.Id)
    }

    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    if (-not $DryRunMode) {
      Write-JsonFile -Value @{
        schema = "skybridge.runner.resume.v1"
        resumedAt = (Get-Date).ToUniversalTime().ToString("o")
        goalFile = $doingGoal.Name
        branch = $branch
        runDir = $runDir
        previousLock = $lockState.Lock
        previousLockStatus = $lockState.Status
        previousLockReason = $lockState.Reason
        host = $env:COMPUTERNAME
        pid = $PID
      } -Path (Join-Path $runDir ("resume-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
      New-GoalLock -GoalFile $doingGoal.Name -Branch $branch -RunDir $runDir -LockPath $lockPath -Reason "resume" | Out-Null
    }

    return @{
      GoalName = $doingGoal.Name
      GoalParts = $goalParts
      Branch = $branch
      RunDir = $runDir
      DoingPath = $doingPath
      ClaimPath = $claimPath
      LockPath = $lockPath
      IsResume = $true
    }
  }

  $goal = Get-ChildItem $ReadyDir -Filter "*.md" | Sort-Object Name | Select-Object -First 1
  if (-not $goal) {
    Write-Host "[yolo-runner] no ready goal."
    return $null
  }

  $goalParts = Get-GoalParts $goal.Name
  $branch = Get-BranchForGoal $goalParts
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $runDir = Join-Path $RunRoot ("{0}-{1}" -f $timestamp, $goalParts.Id)
  $doingPath = Join-Path $DoingDir $goal.Name
  $claimPath = Join-Path $DoingDir ("{0}.claim.json" -f $goal.Name)
  $lockPath = Get-GoalLockPath $claimPath

  New-Item -ItemType Directory -Force -Path $runDir | Out-Null
  Copy-Item $goal.FullName (Join-Path $runDir "goal.md")
  Move-Item $goal.FullName $doingPath

  $claim = @{
    schema = "skybridge.runner.claim.v1"
    goalId = $goalParts.Id
    goalFile = $goal.Name
    branch = $branch
    mode = $EffectiveMode
    maxParallel = $EffectiveMaxParallel
    maxRepairRounds = $EffectiveMaxRepairRounds
    runDir = $runDir
    claimedAt = (Get-Date).ToUniversalTime().ToString("o")
    host = $env:COMPUTERNAME
    pid = $PID
  }
  Write-JsonFile -Value $claim -Path $claimPath
  Write-JsonFile -Value $claim -Path (Join-Path $runDir "claim.json")
  New-GoalLock -GoalFile $goal.Name -Branch $branch -RunDir $runDir -LockPath $lockPath -Reason "claim" | Out-Null

  return @{
    GoalName = $goal.Name
    GoalParts = $goalParts
    Branch = $branch
    RunDir = $runDir
    DoingPath = $doingPath
    ClaimPath = $claimPath
    LockPath = $lockPath
    IsResume = $false
  }
}

function Invoke-OneGoal {
  param([hashtable]$Config)

  $effectiveMaxRepairRounds = [int](Get-ConfigValue $Config "maxRepairRounds" $MaxRepairRounds)
  $effectiveMaxParallel = [int](Get-ConfigValue $Config "maxParallel" $MaxParallel)
  $effectiveLockStaleMinutes = [int](Get-ConfigValue $Config "lockStaleMinutes" $LockStaleMinutes)
  $effectiveMode = [string](Get-ConfigValue $Config "mode" $Mode)
  $effectiveAutoPR = [bool](Get-ConfigValue $Config "autoPR" ([bool]$AutoPR))
  $effectivePush = [bool](Get-ConfigValue $Config "push" $true)
  $effectiveCreatePR = [bool](Get-ConfigValue $Config "createPR" $effectiveAutoPR)
  $effectiveSandbox = [string](Get-ConfigValue $Config "sandbox" "workspace-write")
  $goalConfig = @{}
  if ($Config.ContainsKey("goals") -and $Config["goals"] -is [hashtable]) {
    $goalConfig = $Config["goals"]
  }
  $runConfig = @{}
  if ($Config.ContainsKey("runs") -and $Config["runs"] -is [hashtable]) {
    $runConfig = $Config["runs"]
  }
  $effectiveGoalsReady = [string](Get-ConfigValue $goalConfig "ready" $GoalsReady)
  $effectiveGoalsDoing = [string](Get-ConfigValue $goalConfig "doing" $GoalsDoing)
  $effectiveGoalsDone = [string](Get-ConfigValue $goalConfig "done" $GoalsDone)
  $effectiveGoalsFailed = [string](Get-ConfigValue $goalConfig "failed" $GoalsFailed)
  $effectiveRunRoot = [string](Get-ConfigValue $runConfig "directory" $RunRoot)

  if ($effectiveMaxParallel -ne 1) {
    throw "MaxParallel must remain 1 for this MVP runner."
  }

  Send-RunnerEvent `
    -Type "agent.idle" `
    -Payload @{
      lifecycle = "runner.started"
      mode = $effectiveMode
      maxParallel = $effectiveMaxParallel
      maxRepairRounds = $effectiveMaxRepairRounds
      dryRun = [bool]$DryRun
      redaction = "runner telemetry omits command output, prompts, repair logs and secrets by default"
    }

  New-Item -ItemType Directory -Force -Path $effectiveGoalsReady,$effectiveGoalsDoing,$effectiveGoalsDone,$effectiveGoalsFailed,$effectiveRunRoot | Out-Null

  $workItem = Select-GoalWorkItem `
    -ReadyDir $effectiveGoalsReady `
    -DoingDir $effectiveGoalsDoing `
    -RunRoot $effectiveRunRoot `
    -StaleMinutes $effectiveLockStaleMinutes `
    -EffectiveMaxParallel $effectiveMaxParallel `
    -EffectiveMaxRepairRounds $effectiveMaxRepairRounds `
    -EffectiveMode $effectiveMode `
    -DryRunMode ([bool]$DryRun)

  if (-not $workItem) {
    Send-RunnerEvent `
      -Type "agent.idle" `
      -Payload @{
        lifecycle = "runner.no_ready_goal"
        readyDir = $effectiveGoalsReady
        doingDir = $effectiveGoalsDoing
      }
    return $false
  }

  $goalParts = $workItem.GoalParts
  $branch = $workItem.Branch
  $runDir = $workItem.RunDir
  $doingPath = $workItem.DoingPath
  $claimPath = $workItem.ClaimPath
  $lockPath = $workItem.LockPath
  $correlation = Get-RunnerCorrelation -GoalParts $goalParts -RunDir $runDir

  Send-RunnerEvent `
    -Type "run.started" `
    -Correlation $correlation `
    -Payload @{
      lifecycle = if ($workItem.IsResume) { "goal.resumed" } else { "goal.claimed" }
      goalId = $goalParts.Id
      goalFile = $workItem.GoalName
      branch = $branch
      runDir = $runDir
      mode = $effectiveMode
      maxRepairRounds = $effectiveMaxRepairRounds
      redaction = "goal text and claim internals omitted by default"
    }

  Send-AgentNotice -Title "SkyBridge runner started" -Message "Started goal $($goalParts.Base)" -Priority "default" -Correlation $correlation

  try {
    if ($DryRun) {
      Write-Host "[yolo-runner] dry run selected goal $($workItem.GoalName), branch $branch, run dir $runDir, resume=$($workItem.IsResume)"
      if (-not $workItem.IsResume) {
        Move-Item $doingPath (Join-Path $effectiveGoalsReady (Split-Path $doingPath -Leaf)) -Force
        if (Test-Path $claimPath) {
          Remove-Item $claimPath -Force
        }
        if (Test-Path $lockPath) {
          Remove-Item $lockPath -Force
        }
      }
      return $true
    }

    Switch-ToGoalBranch $branch
    $currentBranch = (git branch --show-current).Trim()
    if ($currentBranch -ne $branch) {
      throw "Current branch '$currentBranch' does not match goal branch '$branch'."
    }

    $goalText = Get-Content $doingPath -Raw
    $prompt = @"
You are running as the SkyBridge autonomous development runner.

Repository workflow:
- Read the goal file and relevant project docs before editing.
- Split work into logical, reviewable subtasks.
- Commit coherent passing subtasks when possible.
- Do not touch secrets, production server config, global config or deployment credentials.
- Do not enable parallel autonomous execution.
- Stop after this goal is handled and summarize commits, checks and risks.

Goal file:

$goalText
"@

    Send-RunnerEvent `
      -Type "tool.started" `
      -Correlation @{
        session_id = $correlation.session_id
        run_id = $correlation.run_id
        tool_call_id = "codex-main"
      } `
      -Payload @{
        lifecycle = "codex.invocation.started"
        tool_name = "codex exec"
        jsonl = "codex.jsonl"
        lastMessage = "last-message.md"
        sandbox = $effectiveSandbox
        prompt_omitted = $true
        redaction = "codex prompt and JSONL output omitted by default"
      }

    $codexExit = Invoke-CodexJson -RunDir $runDir -JsonlName "codex.jsonl" -LastMessageName "last-message.md" -Prompt $prompt -Sandbox $effectiveSandbox
    Send-RunnerEvent `
      -Type $(if ($codexExit -eq 0) { "tool.completed" } else { "tool.failed" }) `
      -Severity $(if ($codexExit -eq 0) { "info" } else { "error" }) `
      -Correlation @{
        session_id = $correlation.session_id
        run_id = $correlation.run_id
        tool_call_id = "codex-main"
      } `
      -Payload @{
        lifecycle = "codex.invocation.finished"
        tool_name = "codex exec"
        exitCode = $codexExit
        jsonl = "codex.jsonl"
        lastMessage = "last-message.md"
        output_omitted = $true
        redaction = "codex stdout, stderr and JSONL output omitted by default"
      }
    if ($codexExit -ne 0) {
      throw "codex exec failed with exit code $codexExit."
    }

    $checkOk = $false
    for ($attempt = 0; $attempt -le $effectiveMaxRepairRounds; $attempt++) {
      $checkToolCallId = "check-$attempt"
      $checkCommand = if (Resolve-CommandPath "just") { "just check" } else { "corepack pnpm check" }
      Send-RunnerEvent `
        -Type "tool.started" `
        -Correlation @{
          session_id = $correlation.session_id
          run_id = $correlation.run_id
          tool_call_id = $checkToolCallId
        } `
        -Payload @{
          lifecycle = "check.started"
          tool_name = "standard-check"
          attempt = $attempt
          command = $checkCommand
          log = ("check-{0}.log" -f $attempt)
          output_omitted = $true
          redaction = "check stdout and stderr omitted by default"
        }
      $checkExit = Invoke-StandardCheck -RunDir $runDir -Attempt $attempt
      Send-RunnerEvent `
        -Type $(if ($checkExit -eq 0) { "tool.completed" } else { "tool.failed" }) `
        -Severity $(if ($checkExit -eq 0) { "info" } else { "warning" }) `
        -Correlation @{
          session_id = $correlation.session_id
          run_id = $correlation.run_id
          tool_call_id = $checkToolCallId
        } `
        -Payload @{
          lifecycle = "check.finished"
          tool_name = "standard-check"
          attempt = $attempt
          command = $checkCommand
          exitCode = $checkExit
          log = ("check-{0}.log" -f $attempt)
          output_omitted = $true
          redaction = "check stdout and stderr omitted by default"
        }
      if ($checkExit -eq 0) {
        $checkOk = $true
        break
      }

      if ($attempt -eq $effectiveMaxRepairRounds) {
        break
      }

      $repairPrompt = @"
The SkyBridge runner standard check failed on attempt $attempt.

Inspect the repository and the latest check log under:
$runDir

Fix the failure with the smallest safe change.
Do not delete tests.
Do not weaken authentication or authorization.
Do not modify secrets, production server configuration or global machine configuration.
After fixing, stop and summarize the change.
"@

      Send-RunnerEvent `
        -Type "tool.started" `
        -Correlation @{
          session_id = $correlation.session_id
          run_id = $correlation.run_id
          tool_call_id = "repair-$attempt"
        } `
        -Payload @{
          lifecycle = "repair.started"
          tool_name = "codex exec"
          attempt = $attempt
          jsonl = ("repair-{0}.jsonl" -f $attempt)
          lastMessage = ("repair-{0}-last-message.md" -f $attempt)
          prompt_omitted = $true
          redaction = "repair prompt, check log contents and Codex output omitted by default"
        }
      $repairExit = Invoke-CodexJson -RunDir $runDir -JsonlName ("repair-{0}.jsonl" -f $attempt) -LastMessageName ("repair-{0}-last-message.md" -f $attempt) -Prompt $repairPrompt -Sandbox $effectiveSandbox
      Send-RunnerEvent `
        -Type $(if ($repairExit -eq 0) { "tool.completed" } else { "tool.failed" }) `
        -Severity $(if ($repairExit -eq 0) { "info" } else { "error" }) `
        -Correlation @{
          session_id = $correlation.session_id
          run_id = $correlation.run_id
          tool_call_id = "repair-$attempt"
        } `
        -Payload @{
          lifecycle = "repair.finished"
          tool_name = "codex exec"
          attempt = $attempt
          exitCode = $repairExit
          jsonl = ("repair-{0}.jsonl" -f $attempt)
          lastMessage = ("repair-{0}-last-message.md" -f $attempt)
          output_omitted = $true
          redaction = "repair stdout, stderr and JSONL output omitted by default"
        }
      if ($repairExit -ne 0) {
        throw "codex repair attempt $attempt failed with exit code $repairExit."
      }
    }

    if (-not $checkOk) {
      throw "Checks failed after $effectiveMaxRepairRounds repair rounds."
    }

    $completedGoal = Complete-GoalState -DoingPath $doingPath -ClaimPath $claimPath -TargetDir $effectiveGoalsDone -LockPath $lockPath
    Write-JsonFile -Value @{
      status = "completed"
      completedAt = (Get-Date).ToUniversalTime().ToString("o")
      branch = $branch
      runDir = $runDir
      goalFile = $completedGoal
    } -Path (Join-Path $runDir "result.json")

    Commit-IfNeeded -Message "chore(goal): complete $($goalParts.Base)" -Paths @(".")

    if ($effectivePush) {
      Push-Branch $branch
    }

    if ($effectiveCreatePR) {
      New-PullRequestIfAvailable -GoalTitle $goalParts.Base -Branch $branch -RunDir $runDir
    }

    Send-RunnerEvent `
      -Type "run.completed" `
      -Correlation $correlation `
      -Payload @{
        lifecycle = "goal.completed"
        goalId = $goalParts.Id
        goalFile = $workItem.GoalName
        branch = $branch
        runDir = $runDir
        checksPassed = $true
      }
    Send-AgentNotice -Title "SkyBridge runner completed" -Message "Completed goal $($goalParts.Base)" -Priority "default" -Correlation $correlation
    return $true
  } catch {
    $err = $_.Exception.Message
    Write-JsonFile -Value @{
      status = "failed"
      failedAt = (Get-Date).ToUniversalTime().ToString("o")
      branch = $branch
      runDir = $runDir
      error = $err
    } -Path (Join-Path $runDir "result.json")

    if (Test-Path $doingPath) {
      Complete-GoalState -DoingPath $doingPath -ClaimPath $claimPath -TargetDir $effectiveGoalsFailed -LockPath $lockPath | Out-Null
    }

    Send-RunnerEvent `
      -Type "run.failed" `
      -Severity "error" `
      -Correlation $correlation `
      -Payload @{
        lifecycle = "goal.failed"
        goalId = $goalParts.Id
        goalFile = $workItem.GoalName
        branch = $branch
        runDir = $runDir
        error_summary = $err
        logs_omitted = $true
        redaction = "full command output and repair logs omitted by default"
      }
    Send-AgentNotice -Title "SkyBridge runner failed" -Message "Goal $($goalParts.Base) failed: $err" -Priority "high" -Correlation $correlation
    throw
  }
}

$config = Import-RunnerConfig $ConfigFile
Initialize-RunnerTelemetry -Config $config

if ($AutoMergeLowRisk) {
  Write-Warning "AutoMergeLowRisk is intentionally not implemented for this MVP."
}

do {
  $processed = Invoke-OneGoal -Config $config
  if (-not $Loop) {
    break
  }

  if (-not $processed) {
    Start-Sleep -Seconds $PollSeconds
  }
} while ($true)
