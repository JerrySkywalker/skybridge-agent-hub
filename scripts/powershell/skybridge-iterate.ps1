[CmdletBinding()]
param(
  [string]$ConfigFile = ".\config\iteration-controller.json",
  [string]$GoalFile,
  [string]$GoalQueue,
  [switch]$One,
  [switch]$DryRun,
  [switch]$CreatePR,
  [switch]$WatchCI,
  [int]$MaxRepairAttempts = -1,
  [switch]$EnableAutoMerge,
  [switch]$NoAutoMerge,
  [string]$SkyBridgeApiBase
)

$ErrorActionPreference = "Stop"

function ConvertTo-PlainObject {
  param([Parameter(Position=0, ValueFromPipeline=$true)]$Value)
  process {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
      $hash = @{}
      foreach ($property in $Value.PSObject.Properties) {
        $hash[$property.Name] = ConvertTo-PlainObject $property.Value
      }
      return $hash
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
      $items = @()
      foreach ($item in $Value) { $items += ConvertTo-PlainObject $item }
      return $items
    }
    return $Value
  }
}

function Import-ControllerConfig {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return ConvertTo-PlainObject (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
  }
  if (Test-Path -LiteralPath ".\config\iteration-controller.example.json") {
    return ConvertTo-PlainObject (Get-Content -LiteralPath ".\config\iteration-controller.example.json" -Raw | ConvertFrom-Json)
  }
  return @{}
}

function Get-NestedValue {
  param($Root, [string[]]$Path, $Default)
  $current = $Root
  foreach ($part in $Path) {
    if ($current -isnot [hashtable] -or -not $current.ContainsKey($part) -or $null -eq $current[$part]) {
      return $Default
    }
    $current = $current[$part]
  }
  return $current
}

function Get-NextGoalFile {
  param([string]$ExplicitGoalFile, [string]$QueuePath)
  if (-not [string]::IsNullOrWhiteSpace($ExplicitGoalFile)) { return $ExplicitGoalFile }
  if ([string]::IsNullOrWhiteSpace($QueuePath) -or -not (Test-Path -LiteralPath $QueuePath)) { return $null }
  return (Get-ChildItem -LiteralPath $QueuePath -Filter *.md -File | Sort-Object Name | Select-Object -First 1).FullName
}

function New-IterationId {
  param([string]$GoalPath)
  $slug = if ($GoalPath) { [IO.Path]::GetFileNameWithoutExtension($GoalPath) } else { "manual" }
  $safeSlug = ($slug -replace "[^A-Za-z0-9._-]", "-").Trim("-")
  return "iter_{0}_{1}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"), $safeSlug
}

function Invoke-BootstrapNotification {
  param([string]$Severity, [string]$Title, [string]$Message)
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title $Title `
    -Message $Message `
    -Severity $Severity | Out-Host
}

function Send-IterationEvent {
  param([string]$ApiBase, [string]$IterationId, [string]$Type, [hashtable]$Payload = @{})
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return }
  try {
    Invoke-RestMethod -Method Post -Uri "$($ApiBase.TrimEnd('/'))/v1/iterations/$IterationId/events" `
      -ContentType "application/json" `
      -Body (@{ type = $Type; payload = $Payload } | ConvertTo-Json -Depth 20) `
      -TimeoutSec 3 | Out-Null
  } catch {
    Write-Host "[iterate] SkyBridge event skipped: $($_.Exception.Message)"
  }
}

function Invoke-CheckedCommand {
  param([string]$Command, [string]$LogFile, [switch]$DryRun)
  if ($DryRun) {
    "DRY RUN: $Command" | Set-Content -LiteralPath $LogFile -Encoding UTF8
    return 0
  }
  $output = & pwsh -NoLogo -NoProfile -Command $Command 2>&1
  $output | Set-Content -LiteralPath $LogFile -Encoding UTF8
  return $LASTEXITCODE
}

$config = Import-ControllerConfig -Path $ConfigFile
$projectId = [string](Get-NestedValue $config @("project", "id") "skybridge-agent-hub")
$repo = [string](Get-NestedValue $config @("project", "repository") "")
$baseBranch = [string](Get-NestedValue $config @("project", "baseBranch") "main")
$branchPrefix = [string](Get-NestedValue $config @("project", "branchPrefix") "ai/")
$queuePath = if ($GoalQueue) { $GoalQueue } else { [string](Get-NestedValue $config @("goals", "queuePath") "goals/ready") }
$codexCommand = [string](Get-NestedValue $config @("codex", "command") "codex")
$sandbox = [string](Get-NestedValue $config @("codex", "sandbox") "workspace-write")
$apiBase = if ($SkyBridgeApiBase) { $SkyBridgeApiBase } else { [string](Get-NestedValue $config @("skybridge", "apiBase") "") }
$maxAttempts = if ($MaxRepairAttempts -ge 0) { $MaxRepairAttempts } else { [int](Get-NestedValue $config @("iteration", "maxRepairAttempts") 3) }
$checkCommands = @(Get-NestedValue $config @("iteration", "localCheckCommands") @("corepack pnpm check"))
$goalPath = Get-NextGoalFile -ExplicitGoalFile $GoalFile -QueuePath $queuePath
$iterationId = New-IterationId -GoalPath $goalPath
$runDir = Join-Path ".\.agent\iterations" $iterationId
$autoMerge = $EnableAutoMerge -and -not $NoAutoMerge

New-Item -ItemType Directory -Force -Path $runDir | Out-Null

if (-not $goalPath) {
  Invoke-BootstrapNotification -Severity "info" -Title "SkyBridge iteration idle" -Message "No goal file was available."
  @{ ok = $true; state = "idle"; iteration_id = $iterationId; dry_run = [bool]$DryRun } | ConvertTo-Json -Depth 8
  exit 0
}

$goalText = Get-Content -LiteralPath $goalPath -Raw
$branchSlug = ([IO.Path]::GetFileNameWithoutExtension($goalPath) -replace "[^A-Za-z0-9._-]", "-").Trim("-")
$branch = "$branchPrefix$branchSlug"
$lastMessage = Join-Path $runDir "last-message.md"
$codexJsonl = Join-Path $runDir "codex.jsonl"
$codexPrompt = @"
Execute this SkyBridge goal as one bounded autonomous iteration.

Safety boundaries:
- do not touch secrets, .env, production config, /opt, server root config or Docker daemon config;
- do not deploy;
- keep changes reviewable and tested;
- commit only coherent passing work.

Goal file: $goalPath

$goalText
"@
$codexArgs = @("exec", "--sandbox", $sandbox, "--ask-for-approval", "never", "--json", "--output-last-message", $lastMessage, $codexPrompt)

$metadata = @{
  iteration_id = $iterationId
  project_id = $projectId
  repo = $repo
  branch = $branch
  base_branch = $baseBranch
  goal_file = $goalPath
  dry_run = [bool]$DryRun
  codex_command = "$codexCommand $($codexArgs[0..6] -join ' ') <prompt>"
  auto_merge = [bool]$autoMerge
}
$metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runDir "metadata.json") -Encoding UTF8

if (-not [string]::IsNullOrWhiteSpace($apiBase)) {
  try {
    Invoke-RestMethod -Method Post -Uri "$($apiBase.TrimEnd('/'))/v1/iterations" -ContentType "application/json" -TimeoutSec 3 -Body (@{
      iteration_id = $iterationId
      project_id = $projectId
      goal_id = [IO.Path]::GetFileNameWithoutExtension($goalPath)
      repo = $repo
      branch = $branch
      base_branch = $baseBranch
      state = "queued"
      attempts = 0
      max_attempts = $maxAttempts
      checks = @()
      auto_merge_enabled = [bool]$autoMerge
    } | ConvertTo-Json -Depth 12) | Out-Null
  } catch {
    Write-Host "[iterate] SkyBridge iteration create skipped: $($_.Exception.Message)"
  }
}

Invoke-BootstrapNotification -Severity "info" -Title "SkyBridge iteration started" -Message "$iterationId on $branch"
Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.started" -Payload $metadata

if ($DryRun) {
  $codexPrompt | Set-Content -LiteralPath (Join-Path $runDir "prompt-preview.md") -Encoding UTF8
  @{ ok = $true; state = "dry_run"; iteration_id = $iterationId; branch = $branch; run_dir = $runDir; codex_command = $metadata.codex_command } | ConvertTo-Json -Depth 8
  exit 0
}

git fetch origin $baseBranch | Out-Null
git checkout -B $branch "origin/$baseBranch"
Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.state_changed" -Payload @{ state = "coding" }

& $codexCommand @codexArgs *> $codexJsonl
if ($LASTEXITCODE -ne 0) {
  Invoke-BootstrapNotification -Severity "urgent" -Title "SkyBridge iteration failed" -Message "$iterationId Codex worker failed."
  Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.failed" -Payload @{ state = "failed"; exit_code = $LASTEXITCODE }
  exit $LASTEXITCODE
}

Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.local_check_started" -Payload @{ state = "local_checking" }
foreach ($command in $checkCommands) {
  $logFile = Join-Path $runDir ("check-{0}.log" -f (($command -replace "[^A-Za-z0-9._-]", "-").Substring(0, [Math]::Min(40, $command.Length))))
  $exitCode = Invoke-CheckedCommand -Command $command -LogFile $logFile
  if ($exitCode -ne 0) {
    Invoke-BootstrapNotification -Severity "warning" -Title "SkyBridge local check failed" -Message "$iterationId failed local check: $command"
    Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.local_check_failed" -Payload @{ command = $command; exit_code = $exitCode }
    exit $exitCode
  }
}
Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.local_check_passed" -Payload @{ checks = $checkCommands.Count }

git add -A
if (-not (git diff --cached --quiet)) {
  git commit -m "chore(iteration): run $([IO.Path]::GetFileNameWithoutExtension($goalPath))"
}
git push -u origin $branch
Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.state_changed" -Payload @{ state = "pushing" }

if ($CreatePR) {
  $prUrl = gh pr create --draft --base $baseBranch --head $branch --title "Autonomous iteration: $branchSlug" --body "Created by SkyBridge Autonomous Iteration Controller. Raw logs are local only under $runDir."
  Send-IterationEvent -ApiBase $apiBase -IterationId $iterationId -Type "iteration.pr_opened" -Payload @{ pr_url = $prUrl; branch = $branch }
}

if ($WatchCI) {
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-ci-guardian.ps1" -CurrentBranch -MaxRepairAttempts $maxAttempts -SkyBridgeApiBase $apiBase
}

@{ ok = $true; state = "completed"; iteration_id = $iterationId; branch = $branch; run_dir = $runDir } | ConvertTo-Json -Depth 8
