param(
  [ValidateSet("ThesisYOLO", "Conservative")]
  [string]$Mode = "ThesisYOLO",

  [int]$MaxRepairRounds = 3,

  [switch]$AutoPR,

  [switch]$AutoMergeLowRisk,

  [switch]$NotifyOnlyImportant = $true,

  [string]$GoalsReady = ".\goals\ready",

  [string]$GoalsDoing = ".\goals\doing",

  [string]$GoalsDone = ".\goals\done",

  [string]$GoalsFailed = ".\goals\failed"
)

$ErrorActionPreference = "Stop"

function Send-AgentNotice {
  param([string]$Title, [string]$Message, [string]$Priority = "default")
  $notify = ".\scripts\powershell\notify-ntfy.ps1"
  if (Test-Path $notify) {
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $notify -Title $Title -Message $Message -Priority $Priority
  } else {
    Write-Host "[$Title] $Message"
  }
}

New-Item -ItemType Directory -Force -Path $GoalsReady,$GoalsDoing,$GoalsDone,$GoalsFailed | Out-Null

$goal = Get-ChildItem $GoalsReady -Filter "*.md" | Sort-Object Name | Select-Object -First 1
if (-not $goal) {
  Write-Host "[yolo-runner] no ready goal."
  exit 0
}

$slug = [IO.Path]::GetFileNameWithoutExtension($goal.Name)
$branch = "ai/$slug"
$doingPath = Join-Path $GoalsDoing $goal.Name

Move-Item $goal.FullName $doingPath
Send-AgentNotice -Title "SkyBridge YOLO started" -Message "Started goal $slug" -Priority "default"

try {
  git checkout -b $branch

  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\run-goal.ps1 `
    -GoalFile $doingPath `
    -Mode WorkspaceAuto

  $checkOk = $false
  for ($i = 0; $i -le $MaxRepairRounds; $i++) {
    pnpm check
    if ($LASTEXITCODE -eq 0) {
      $checkOk = $true
      break
    }

    if ($i -eq $MaxRepairRounds) { break }

    $repairPrompt = @"
The previous standard check failed.

Please inspect the repository and fix the failures with the smallest safe change.
Do not delete tests.
Do not modify production secrets or deployment files unless directly necessary.
After fixing, stop and summarize.
"@
    codex exec --sandbox workspace-write --ask-for-approval never $repairPrompt
  }

  if (-not $checkOk) {
    throw "Checks failed after $MaxRepairRounds repair rounds."
  }

  git add .
  git commit -m "feat: complete goal $slug"
  git status --short

  if ($AutoPR) {
    git push -u origin $branch
    gh pr create --fill --label ai-generated --label yolo
  }

  Move-Item $doingPath (Join-Path $GoalsDone (Split-Path $doingPath -Leaf))
  Send-AgentNotice -Title "SkyBridge YOLO completed" -Message "Completed goal $slug" -Priority "default"
} catch {
  $err = $_.Exception.Message
  Move-Item $doingPath (Join-Path $GoalsFailed (Split-Path $doingPath -Leaf)) -Force
  Send-AgentNotice -Title "SkyBridge YOLO failed" -Message "Goal $slug failed: $err" -Priority "high"
  throw
}
