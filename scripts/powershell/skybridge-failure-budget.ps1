param(
  [ValidateSet("status", "preview", "classify", "gate", "retry-gate", "replacement-gate", "suppress-repeated-blocker-preview", "report", "safe-summary")]
  [string]$Command = "status",
  [string]$Scenario = "nonzero_no_mutation",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function New-FailureClassification([string]$FailureClass) {
  $changed = @()
  $prCreated = $false
  $rawArtifact = $false
  $secret = $false
  switch ($FailureClass) {
    "timeout_with_changes" { $changed = @("packages/event-schema/src/reliability.ts") }
    "nonzero_with_changes" { $changed = @("apps/server/src/index.ts") }
    "dirty_worktree" { $changed = @("dirty-worktree-fixture") }
    "disallowed_path_change" { $changed = @(".env") }
    "pr_created_hold" { $prCreated = $true }
    "raw_artifact_detected" { $rawArtifact = $true }
    "secret_detected" { $secret = $true }
  }
  [ordered]@{
    schema = "skybridge.failure_classification.v1"
    run_id = "goal-219-fixture-run"
    workunit_id = "goal-219-fixture-workunit"
    failure_class = $FailureClass
    changed_files = $changed
    pr_created = $prCreated
    raw_artifact_detected = $rawArtifact
    secret_detected = $secret
    token_printed = $false
  }
}

function New-FailureBudgetPolicy {
  [ordered]@{
    schema = "skybridge.failure_budget.v1"
    timeout_budget = 1
    nonzero_exit_budget = 1
    no_change_budget = 1
    dirty_worktree_budget = 0
    resource_gate_block_budget = 3
    repeated_blocker_suppression = $true
    retry_requires_explicit_authorization = $true
    replacement_requires_no_mutation_classification = $true
    max_retries_per_workunit = 0
    max_replacements_per_workunit = 1
    no_silent_rerun = $true
    no_retry_after_pr_created = $true
    no_retry_after_raw_artifact = $true
    no_retry_after_disallowed_change = $true
    no_retry_after_secret_detected = $true
    token_printed = $false
  }
}

function Resolve-FailureClass([string]$InputScenario) {
  $known = @(
    "no_failure",
    "timeout_no_mutation",
    "timeout_with_changes",
    "nonzero_no_mutation",
    "nonzero_with_changes",
    "no_change_result",
    "dirty_worktree",
    "disallowed_path_change",
    "pr_created_hold",
    "raw_artifact_detected",
    "secret_detected",
    "resource_gate_blocked",
    "repeated_blocker",
    "unknown_unsafe",
    "token_printed_true"
  )
  if ($known -contains $InputScenario) { return $InputScenario }
  if ($InputScenario -eq "repeated_resource_gate_block") { return "repeated_blocker" }
  return "unknown_unsafe"
}

function New-RetryGate($classification) {
  $blockedClasses = @(
    "timeout_with_changes",
    "nonzero_with_changes",
    "dirty_worktree",
    "disallowed_path_change",
    "pr_created_hold",
    "raw_artifact_detected",
    "secret_detected",
    "unknown_unsafe",
    "token_printed_true"
  )
  [ordered]@{
    schema = "skybridge.retry_authorization_gate.v1"
    workunit_id = $classification.workunit_id
    retry_allowed = $false
    automatic_retry_allowed = $false
    explicit_operator_authorization_required = $true
    no_silent_rerun = $true
    no_retry_after_pr_created = $true
    blocked = ($blockedClasses -contains $classification.failure_class) -or $classification.pr_created -or $classification.raw_artifact_detected -or $classification.secret_detected
    token_printed = $false
  }
}

function New-ReplacementGate($classification) {
  $allowFutureExplicitReplacement = $classification.failure_class -in @("timeout_no_mutation", "nonzero_no_mutation") -and
    -not $classification.pr_created -and
    @($classification.changed_files).Count -eq 0 -and
    -not $classification.raw_artifact_detected -and
    -not $classification.secret_detected
  [ordered]@{
    schema = "skybridge.replacement_authorization_gate.v1"
    workunit_id = $classification.workunit_id
    replacement_allowed = [bool]$allowFutureExplicitReplacement
    automatic_replacement_allowed = $false
    requires_no_mutation_classification = $true
    explicit_operator_authorization_required = $true
    token_printed = $false
  }
}

function New-FailureBudgetReport([string]$InputScenario) {
  $class = Resolve-FailureClass $InputScenario
  $classification = New-FailureClassification $class
  $retry = New-RetryGate $classification
  $replacement = New-ReplacementGate $classification
  $blockers = @()
  if ($retry.blocked -or -not $replacement.replacement_allowed) {
    $blockers += [ordered]@{
      schema = "skybridge.failure_budget_blocker.v1"
      blocker_id = "failure-budget-$class"
      failure_class = $class
      reason = "Automatic retry is refused; future replacement requires explicit operator authorization when policy allows it."
      retry_blocked = $true
      replacement_blocked = -not $replacement.replacement_allowed
      token_printed = $false
    }
  }
  [ordered]@{
    schema = "skybridge.failure_budget_report.v1"
    policy = New-FailureBudgetPolicy
    classifications = @($classification)
    retry_gate = $retry
    replacement_gate = $replacement
    blockers = $blockers
    ready_for_controlled_release = $true
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    queue_apply_enabled = $false
    token_printed = $false
  }
}

$report = New-FailureBudgetReport $Scenario
$output = switch ($Command) {
  "classify" { $report.classifications[0] }
  "retry-gate" { $report.retry_gate }
  "replacement-gate" { $report.replacement_gate }
  "gate" { [ordered]@{ retry_gate = $report.retry_gate; replacement_gate = $report.replacement_gate; token_printed = $false } }
  "suppress-repeated-blocker-preview" { New-FailureBudgetReport "repeated_blocker" }
  "safe-summary" { [ordered]@{ ok = $true; no_silent_rerun = $true; automatic_retry_allowed = $false; token_printed = $false } }
  default { $report }
}

if ($Command -eq "report") {
  $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
  $dir = Join-Path $root ".agent\tmp\audit"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $output | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "failure-budget-report.json")
}

$output | ConvertTo-Json -Depth 20
