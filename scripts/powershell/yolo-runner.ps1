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

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

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
    [string]$Priority = "default"
  )

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
    [string]$TargetDir
  )

  $targetGoal = Join-Path $TargetDir (Split-Path $DoingPath -Leaf)
  Move-Item $DoingPath $targetGoal -Force

  if (Test-Path $ClaimPath) {
    $targetClaim = Join-Path $TargetDir (Split-Path $ClaimPath -Leaf)
    Move-Item $ClaimPath $targetClaim -Force
  }

  return $targetGoal
}

function Invoke-OneGoal {
  param([hashtable]$Config)

  $effectiveMaxRepairRounds = [int](Get-ConfigValue $Config "maxRepairRounds" $MaxRepairRounds)
  $effectiveMaxParallel = [int](Get-ConfigValue $Config "maxParallel" $MaxParallel)
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

  New-Item -ItemType Directory -Force -Path $effectiveGoalsReady,$effectiveGoalsDoing,$effectiveGoalsDone,$effectiveGoalsFailed,$effectiveRunRoot | Out-Null

  $goal = Get-ChildItem $effectiveGoalsReady -Filter "*.md" | Sort-Object Name | Select-Object -First 1
  if (-not $goal) {
    Write-Host "[yolo-runner] no ready goal."
    return $false
  }

  $goalParts = Get-GoalParts $goal.Name
  $branch = Get-BranchForGoal $goalParts
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $runDir = Join-Path $effectiveRunRoot ("{0}-{1}" -f $timestamp, $goalParts.Id)
  $doingPath = Join-Path $effectiveGoalsDoing $goal.Name
  $claimPath = Join-Path $effectiveGoalsDoing ("{0}.claim.json" -f $goal.Name)

  New-Item -ItemType Directory -Force -Path $runDir | Out-Null
  Copy-Item $goal.FullName (Join-Path $runDir "goal.md")
  Move-Item $goal.FullName $doingPath

  $claim = @{
    schema = "skybridge.runner.claim.v1"
    goalId = $goalParts.Id
    goalFile = $goal.Name
    branch = $branch
    mode = $effectiveMode
    maxParallel = $effectiveMaxParallel
    maxRepairRounds = $effectiveMaxRepairRounds
    runDir = $runDir
    claimedAt = (Get-Date).ToUniversalTime().ToString("o")
    host = $env:COMPUTERNAME
    pid = $PID
  }
  Write-JsonFile -Value $claim -Path $claimPath
  Write-JsonFile -Value $claim -Path (Join-Path $runDir "claim.json")

  Send-AgentNotice -Title "SkyBridge runner started" -Message "Started goal $($goalParts.Base)" -Priority "default"

  try {
    if ($DryRun) {
      Write-Host "[yolo-runner] dry run selected goal $($goal.Name), branch $branch, run dir $runDir"
      Move-Item $doingPath (Join-Path $effectiveGoalsReady (Split-Path $doingPath -Leaf)) -Force
      if (Test-Path $claimPath) {
        Remove-Item $claimPath -Force
      }
      return $true
    }

    Switch-ToGoalBranch $branch

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

    $codexExit = Invoke-CodexJson -RunDir $runDir -JsonlName "codex.jsonl" -LastMessageName "last-message.md" -Prompt $prompt -Sandbox $effectiveSandbox
    if ($codexExit -ne 0) {
      throw "codex exec failed with exit code $codexExit."
    }

    $checkOk = $false
    for ($attempt = 0; $attempt -le $effectiveMaxRepairRounds; $attempt++) {
      $checkExit = Invoke-StandardCheck -RunDir $runDir -Attempt $attempt
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

      $repairExit = Invoke-CodexJson -RunDir $runDir -JsonlName ("repair-{0}.jsonl" -f $attempt) -LastMessageName ("repair-{0}-last-message.md" -f $attempt) -Prompt $repairPrompt -Sandbox $effectiveSandbox
      if ($repairExit -ne 0) {
        throw "codex repair attempt $attempt failed with exit code $repairExit."
      }
    }

    if (-not $checkOk) {
      throw "Checks failed after $effectiveMaxRepairRounds repair rounds."
    }

    $completedGoal = Complete-GoalState -DoingPath $doingPath -ClaimPath $claimPath -TargetDir $effectiveGoalsDone
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

    Send-AgentNotice -Title "SkyBridge runner completed" -Message "Completed goal $($goalParts.Base)" -Priority "default"
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
      Complete-GoalState -DoingPath $doingPath -ClaimPath $claimPath -TargetDir $effectiveGoalsFailed | Out-Null
    }

    Send-AgentNotice -Title "SkyBridge runner failed" -Message "Goal $($goalParts.Base) failed: $err" -Priority "high"
    throw
  }
}

$config = Import-RunnerConfig $ConfigFile

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
