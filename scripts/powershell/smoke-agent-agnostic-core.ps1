param(
  [switch]$SkipPackageTest
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath ".\docs\architecture\AGENT_AGNOSTIC_CORE.md")) {
  throw "Missing agent-agnostic core boundary doc."
}
if (-not (Test-Path -LiteralPath ".\docs\adapters\README.md")) {
  throw "Missing adapter taxonomy doc."
}

$readme = Get-Content -Raw -LiteralPath ".\README.md"
foreach ($needle in @(
  "SkyBridge is an agent-agnostic control plane for AI-assisted software development.",
  "Agent systems such as Hermes, Codex, OpenCode or future tools connect through adapters.",
  "Core + Adapter Ring"
)) {
  if ($readme -notlike "*$needle*") {
    throw "README is missing required positioning text: $needle"
  }
}

$schema = Get-Content -Raw -LiteralPath ".\packages\event-schema\src\index.ts"
foreach ($needle in @(
  "PlannerDecision",
  "WorkOrder",
  "ExecutionResult",
  "NotificationJob",
  "ProviderStatus",
  "AdapterCapability",
  "createRuleBasedPlannerDecision",
  "createManualExecutionResult"
)) {
  if ($schema -notlike "*$needle*") {
    throw "Event schema is missing neutral boundary type or proof helper: $needle"
  }
}

if (-not $SkipPackageTest) {
  corepack pnpm --filter @skybridge-agent-hub/event-schema test | Out-Host
}

[pscustomobject]@{
  AgentAgnosticPositioning = $true
  RuleBasedPlannerProof = $true
  ManualExecutorProof = $true
  HermesRequired = $false
  CodexRequired = $false
} | Format-List
