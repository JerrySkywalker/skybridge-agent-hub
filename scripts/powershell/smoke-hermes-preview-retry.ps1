[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-hermes-preview-retry-" + [Guid]::NewGuid().ToString("n"))
$attemptFile = Join-Path $tempDir "attempt.txt"
$planScript = Join-Path $tempDir "fake-plan.ps1"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
  @'
[CmdletBinding()]
param(
  [string]$ApiBase,
  [string]$ProjectId,
  [string]$MasterGoalId,
  [string]$Title,
  [string]$Description,
  [string]$PlannerMode,
  [switch]$DryRun,
  [switch]$Json,
  [string]$ConstraintsJson,
  [string]$StateMode,
  [int]$TimeoutSeconds,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$FixtureFile
)

$attemptPath = $env:SKYBRIDGE_RETRY_ATTEMPT_FILE
$attempt = 1
if (Test-Path -LiteralPath $attemptPath -PathType Leaf) {
  $attempt = [int](Get-Content -Raw -LiteralPath $attemptPath) + 1
}
Set-Content -LiteralPath $attemptPath -Value ([string]$attempt) -Encoding ASCII
if ($attempt -eq 1) {
  Write-Error "504 Gateway Time-out from /v1/responses"
  exit 1
}

$proposal = [pscustomobject]@{
  proposal_id = "proposal-retry-smoke"
  title = "Retry smoke proposal"
  risk = "low"
  task_type = "docs"
  policy_decision = "accepted_for_preview"
  policy_reasons = @()
  expected_files = @("docs/dev/RETRY_SMOKE.md")
  acceptance_criteria = @("Retry succeeds.")
  evidence_requirements = @("Wrapper reports retry_needed=true.")
  required_capabilities = @("codex")
  dedupe_key = "retry-smoke"
  rationale = "Fixture proves bounded retry."
}
$adapter = [pscustomobject]@{
  provider = "hermes"
  model = "fixture"
  runtime_mode = "fixture"
  planner_mode = "hermes-preview"
  tool_execution_mode = "disabled"
  prompt_version = "hermes-assisted-proposal-v1"
  input_state_hash = "retryfixture"
}
[pscustomobject]@{
  ok = $true
  mode = "dry-run"
  planner_mode = "hermes-preview"
  master_goal = [pscustomobject]@{ constraints = @("one") }
  planning_session = [pscustomobject]@{ proposals = @($proposal) }
  planner_adapter = $adapter
  proposals = @($proposal)
} | ConvertTo-Json -Depth 20 -Compress
'@ | Set-Content -LiteralPath $planScript -Encoding UTF8

  $env:SKYBRIDGE_RETRY_ATTEMPT_FILE = $attemptFile
  $result = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-preview.ps1 `
    -ApiBase http://127.0.0.1:1 `
    -ProjectId retry-smoke `
    -MasterGoalId retry-smoke-goal `
    -Title "Hermes retry smoke" `
    -SkipHermesHealthCheck `
    -PlanScriptPath $planScript `
    -MaxHermesAttempts 2 `
    -RetryDelaySeconds 0 `
    -TimeoutSeconds 5 `
    -Json | ConvertFrom-Json

  if ($result.summary.retry_needed -ne $true) { throw "Expected retry_needed=true." }
  if ($result.summary.hermes_attempts -ne 2) { throw "Expected two Hermes attempts." }
  if ($result.summary.proposal_count -ne 1) { throw "Expected one proposal." }
  if ($result.summary.token_printed -ne $false) { throw "Expected token_printed=false." }

  $summary = [pscustomobject]@{
    ok = $true
    hermes_attempts = $result.summary.hermes_attempts
    retry_needed = $result.summary.retry_needed
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  Remove-Item Env:\SKYBRIDGE_RETRY_ATTEMPT_FILE -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
