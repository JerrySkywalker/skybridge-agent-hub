. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-reject-unsafe-$([guid]::NewGuid().ToString('N'))"
$candidateRoot = Join-Path (Join-Path $RepoRoot $outputDir) "fixture"
New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
$candidatePath = Join-Path $candidateRoot "unsafe-generated-goal.md"
$unsafe = @'
```json
{
  "schema": "skybridge.generated_goal_metadata.v1",
  "goal_id": "../unsafe",
  "title": "Unsafe generated goal",
  "order": 1,
  "risk": "high",
  "task_type": "arbitrary-shell",
  "allowed_task_types": ["arbitrary-shell"],
  "blocked_task_types": [],
  "requires": [],
  "expected_outputs": [],
  "advance_gate": "none",
  "generated_by": "fixture",
  "generation_provider": "fixture",
  "source_campaign_id": "goal-append-fixture-campaign-355",
  "source_project_id": "skybridge-agent-hub",
  "goal_budget_remaining": 1,
  "human_review_required": false,
  "import_allowed": true,
  "execution_allowed": true,
  "token_printed": false
}
```

# Unsafe generated goal

## Context
Unsafe fixture.

## Mission
Run arbitrary shell.

## Hard Safety Boundaries
None.

## Allowed Scope
Unsafe.

## Forbidden Scope
None.

## Implementation Requirements
Unsafe.

## Validation Requirements
Unsafe.

## CI/CD Requirements
Unsafe.

## Manual Milestone Script Requirement
Unsafe.

## Evidence Requirements
Unsafe.

## Final Report Requirements
Unsafe.

## No-Execution Statement
This candidate is intentionally unsafe for smoke rejection.

token_printed=false
'@
Set-Content -LiteralPath $candidatePath -Value $unsafe -Encoding UTF8

$relativeCandidate = $candidatePath.Substring($RepoRoot.Length + 1)
$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "review-preview",
  "-CandidatePath", $relativeCandidate,
  "-OutputDir", $outputDir
)
foreach ($expected in @("candidate_metadata_invalid", "candidate_safety_invalid")) {
  if (-not (@($result.blockers) -contains $expected)) { throw "Missing unsafe blocker: $expected" }
}
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-TokenPrintedFalse $result

$pathResult = Invoke-JsonScript "skybridge-goal-append.ps1" @("-Command", "review-preview", "-CandidatePath", "..\bad.md", "-OutputDir", $outputDir)
if (-not (@($pathResult.blockers) -contains "candidate_path_traversal")) { throw "Path traversal was not rejected." }
Assert-TokenPrintedFalse $pathResult

Complete-Smoke "goal-append-reject-unsafe"
