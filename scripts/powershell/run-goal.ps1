param(
  [Parameter(Mandatory=$true)]
  [string]$GoalFile,

  [ValidateSet("WorkspaceAuto", "ContainerYolo")]
  [string]$Mode = "WorkspaceAuto",

  [string]$CodexCommand = "codex",

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GoalFile)) {
  throw "Goal file not found: $GoalFile"
}

$goalText = Get-Content $GoalFile -Raw
$repoRoot = (Resolve-Path ".").Path
$agentDir = Join-Path $repoRoot ".agent"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null

$lastMessage = Join-Path $agentDir "last-message.md"
$jsonl = Join-Path $agentDir ("codex-run-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".jsonl")

Write-Host "[run-goal] goal: $GoalFile"
Write-Host "[run-goal] mode: $Mode"

if ($DryRun) {
  Write-Host $goalText
  exit 0
}

if ($Mode -eq "WorkspaceAuto") {
  & $CodexCommand exec `
    --sandbox workspace-write `
    --ask-for-approval never `
    --json `
    --output-last-message $lastMessage `
    $goalText | Tee-Object -FilePath $jsonl
} else {
  Write-Warning "ContainerYolo mode assumes you are already inside a disposable container."
  & $CodexCommand exec `
    --dangerously-bypass-approvals-and-sandbox `
    --json `
    --output-last-message $lastMessage `
    $goalText | Tee-Object -FilePath $jsonl
}

Write-Host "[run-goal] last message: $lastMessage"
Write-Host "[run-goal] jsonl: $jsonl"
