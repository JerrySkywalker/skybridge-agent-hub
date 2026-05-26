[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$runDir = Join-Path ".\.agent\tmp" ("planner-dedupe-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$statePath = Join-Path $runDir "compact-state.json"
$fixturePath = Join-Path $runDir "planner-decision.json"

& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\build-planner-compact-state.ps1" -Fixture -Json |
  Set-Content -LiteralPath $statePath -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "failed to build fixture compact state" }

@"
{
  "decision": "continue",
  "reason": "Fixture chooses a new docs task because docs/planner-adapter is already in do_not_repeat.",
  "task": {
    "title": "Document merge coordinator planner feedback",
    "task_type": "docs",
    "risk": "low",
    "prompt": "Update docs only with a concise note about planner compact state feedback.",
    "allowed_paths": ["docs/automation/"],
    "blocked_paths": [".env", ".agent/", ".data/", "deploy/", "production/"],
    "validation": ["corepack pnpm check"],
    "dedupe_key": "docs/merge-coordinator-planner-feedback",
    "expected_files": ["docs/automation/PR_LIFECYCLE_POLICY.md"],
    "depends_on": [],
    "advances_acceptance": "Adds non-repeating planner feedback documentation.",
    "merge_strategy": "auto_pr_auto_merge"
  },
  "stop_criteria_status": ["fixture complete"]
}
"@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8

$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-hermes-planner.ps1" -DryRun -FixtureFile $fixturePath -CompactStateFile $statePath -Json
if ($LASTEXITCODE -ne 0) { throw "planner dedupe smoke failed" }
$parsed = $output | ConvertFrom-Json
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json

if (@($state.do_not_repeat) -contains $parsed.decision.task.dedupe_key) {
  throw "Planner selected repeated dedupe_key $($parsed.decision.task.dedupe_key)."
}
if ($parsed.decision.task.dedupe_key -eq "docs/planner-adapter") {
  throw "Planner repeated the completed PlannerAdapter runbook task."
}
if (-not $parsed.decision.task.expected_files -or -not $parsed.decision.task.merge_strategy) {
  throw "Planner decision did not include expected_files and merge_strategy."
}

Write-Host "[hermes-planner-dedupe-smoke] ok dedupe=$($parsed.decision.task.dedupe_key)"
