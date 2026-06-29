$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$OperatorTuiReviewConfirmation = "I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION"
$OperatorTuiAppendConfirmation = "I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION"
$OperatorTuiCandidateOutputDir = ".agent/tmp/operator-tui/candidate-flow"

function Invoke-OperatorTuiCargoCheck {
  $cargo = Get-Command cargo -ErrorAction SilentlyContinue
  if (-not $cargo) {
    throw "cargo is required for operator TUI smokes."
  }

  & cargo check --manifest-path apps/operator-tui/Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw "operator TUI cargo check failed." }
}

function Invoke-OperatorTuiSnapshot(
  [string]$Name,
  [ValidateSet("fixture", "local", "cloud", "local-cloud")]
  [string]$Mode = "fixture",
  [string]$OutputDir = ""
) {
  Invoke-OperatorTuiCargoCheck

  if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = if ($Mode -eq "local-cloud") {
      ".agent/tmp/operator-tui/local-cloud"
    } else {
      ".agent/tmp/operator-tui/$Name"
    }
  }

  $modeArg = "--$Mode"
  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- $modeArg --snapshot --write-report --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI snapshot run failed." }

  $snapshotPath = Join-Path $RepoRoot "$OutputDir/operator-tui-snapshot.txt"
  $statePath = Join-Path $RepoRoot "$OutputDir/operator-tui-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/operator-tui-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/operator-tui-report.md"

  foreach ($path in @($snapshotPath, $statePath, $reportPath, $reportMarkdownPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI artifact: $path" }
  }

  $snapshotText = Get-Content -Raw -LiteralPath $snapshotPath
  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  Assert-NoUnsafeText $snapshotText
  Assert-NoUnsafeText $reportMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

  Assert-OperatorTuiShape -State $state -Report $report -SnapshotText $snapshotText
  Assert-OperatorTuiNoMutation -State $state -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    snapshot_path = $snapshotPath
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    snapshot_text = $snapshotText
    state = $state
    report = $report
  }
}

function Invoke-OperatorTuiCandidateFlow(
  [string]$Name,
  [string[]]$Actions,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiCandidateOutputDir,
  [string]$ReviewConfirm = "",
  [string]$AppendConfirm = ""
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiCandidateArtifacts -OutputDir $OutputDir }

  foreach ($action in $Actions) {
    $args = @(
      "--candidate-flow",
      "--candidate-action",
      $action,
      "--snapshot",
      "--write-report",
      "--output-dir",
      $OutputDir
    )
    if (-not [string]::IsNullOrWhiteSpace($ReviewConfirm)) {
      $args += @("--review-confirm", $ReviewConfirm)
    }
    if (-not [string]::IsNullOrWhiteSpace($AppendConfirm)) {
      $args += @("--append-confirm", $AppendConfirm)
    }

    & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "operator TUI candidate action failed: $action" }
  }

  $snapshotPath = Join-Path $RepoRoot "$OutputDir/operator-tui-candidate-snapshot.txt"
  $statePath = Join-Path $RepoRoot "$OutputDir/operator-tui-candidate-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/operator-tui-candidate-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/operator-tui-candidate-report.md"
  $generatedRefPath = Join-Path $RepoRoot "$OutputDir/generated-candidate.md"
  $stateAliasPath = Join-Path $RepoRoot "$OutputDir/candidate-state.json"
  $reportAliasPath = Join-Path $RepoRoot "$OutputDir/candidate-report.md"

  foreach ($path in @($snapshotPath, $statePath, $reportPath, $reportMarkdownPath, $generatedRefPath, $stateAliasPath, $reportAliasPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI candidate artifact: $path" }
  }

  $snapshotText = Get-Content -Raw -LiteralPath $snapshotPath
  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $generatedRef = Get-Content -Raw -LiteralPath $generatedRefPath
  Assert-NoUnsafeText $snapshotText
  Assert-NoUnsafeText $reportMarkdown
  Assert-NoUnsafeText $generatedRef

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

  Assert-OperatorTuiCandidateShape -State $state -Report $report -SnapshotText $snapshotText
  Assert-OperatorTuiCandidateNoExecution -State $state -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    snapshot_path = $snapshotPath
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    generated_ref_path = $generatedRefPath
    snapshot_text = $snapshotText
    state = $state
    report = $report
  }
}

function Clear-OperatorTuiCandidateArtifacts([string]$OutputDir = $OperatorTuiCandidateOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))
  $hermesDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/hermes-planner-provider/operator-tui-candidate-flow"))
  $appendDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/goal-append/operator-tui-candidate-flow"))

  foreach ($path in @($operatorDir, $hermesDir, $appendDir)) {
    if (-not $path.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove non-temp operator TUI artifact path: $path"
    }
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

function Assert-OperatorTuiShape($State, $Report, [string]$SnapshotText) {
  if ($State.schema -ne "skybridge.operator_tui_state.v1") { throw "Unexpected operator TUI state schema." }
  if ($Report.schema -ne "skybridge.operator_tui_report.v1") { throw "Unexpected operator TUI report schema." }
  if ($Report.state_schema -ne $State.schema) { throw "Operator TUI report/state schema mismatch." }
  Assert-True $State.read_only "state.read_only"
  Assert-True $State.safety.read_only "state.safety.read_only"

  Assert-OperatorTuiPanels -Panels $Report.panels_rendered -SnapshotText $SnapshotText
  Assert-OperatorTuiActions -Report $Report
}

function Assert-OperatorTuiCandidateShape($State, $Report, [string]$SnapshotText) {
  if ($State.schema -ne "skybridge.operator_tui_candidate_state.v1") { throw "Unexpected candidate state schema." }
  if ($Report.schema -ne "skybridge.operator_tui_candidate_flow_report.v1") { throw "Unexpected candidate report schema." }
  if ($Report.mode -ne "candidate-flow") { throw "Candidate report must use candidate-flow mode." }
  Assert-OperatorTuiPanels -Panels $Report.panels_rendered -SnapshotText $SnapshotText
  Assert-OperatorTuiActions -Report $Report
  Assert-True $Report.local_state_loaded "candidate.local_state_loaded"
  Assert-True $Report.cloud_state_loaded "candidate.cloud_state_loaded"
  Assert-True $Report.cloud_parity_shown "candidate.cloud_parity_shown"
}

function Assert-OperatorTuiPanels($Panels, [string]$SnapshotText) {
  $requiredPanels = @(
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer"
  )
  $panelNames = @($Panels | ForEach-Object { [string]$_ })
  foreach ($panel in $requiredPanels) {
    if ($panelNames -notcontains $panel) { throw "Missing panel: $panel" }
    if ($SnapshotText -notmatch [regex]::Escape($panel)) { throw "Snapshot text missing panel: $panel" }
  }
}

function Assert-OperatorTuiActions($Report) {
  $disabledActions = @($Report.disabled_actions | ForEach-Object { [string]$_.action })
  foreach ($action in @(
    "preview_bounded_action",
    "start_one_goal",
    "safe_pause",
    "abort_terminate"
  )) {
    if ($disabledActions -notcontains $action) { throw "Disabled action missing: $action" }
  }

  $activeActions = @($Report.active_actions | ForEach-Object { [string]$_.action })
  $expectedActive = @(
    "refresh_local_cloud_state",
    "generate_candidate_fixture",
    "validate_candidate",
    "review_candidate",
    "append_candidate",
    "copy_safe_summary",
    "quit"
  )
  foreach ($action in $expectedActive) {
    if ($activeActions -notcontains $action) { throw "Active action missing: $action" }
  }
  foreach ($action in $activeActions) {
    if ($action -notin $expectedActive) { throw "Unexpected active operator TUI action: $action" }
  }

  foreach ($entry in @($Report.disabled_actions)) {
    $reasons = @($entry.disabled_reasons | ForEach-Object { [string]$_ })
    foreach ($reason in @(
      "requires_mg368d_single_step_gate",
      "execution_apply_disabled",
      "mutation_not_allowed_for_execution",
      "worker_loop_forbidden",
      "queue_runner_forbidden"
    )) {
      if ($reasons -notcontains $reason) { throw "Disabled action $($entry.action) missing reason: $reason" }
    }
  }
}

function Assert-OperatorTuiNoMutation($State, $Report) {
  Assert-False $Report.mutation_attempted "mutation_attempted"
  Assert-False $Report.append_attempted "append_attempted"
  Assert-False $Report.approval_attempted "approval_attempted"
  Assert-False $Report.task_created "task_created"
  Assert-False $Report.task_claimed "task_claimed"
  Assert-False $Report.execution_started "execution_started"
  Assert-False $Report.branch_created "branch_created"
  Assert-False $Report.pr_created "pr_created"
  Assert-False $Report.merge_performed "merge_performed"
  Assert-False $Report.deploy_triggered "deploy_triggered"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-TokenPrintedFalse $Report

  Assert-False $State.safety.mutation_attempted "state.safety.mutation_attempted"
  Assert-False $State.safety.append_attempted "state.safety.append_attempted"
  Assert-False $State.safety.approval_attempted "state.safety.approval_attempted"
  Assert-False $State.safety.token_printed "state.safety.token_printed"
  Assert-False $State.safety.auto_merge_enabled "state.safety.auto_merge_enabled"
  Assert-False $State.safety.release_created "state.safety.release_created"
  Assert-False $State.safety.tag_created "state.safety.tag_created"
  Assert-False $State.safety.asset_uploaded "state.safety.asset_uploaded"
  Assert-False $State.safety.worker_loop_started "state.safety.worker_loop_started"
  Assert-False $State.safety.queue_runner_started "state.safety.queue_runner_started"
  Assert-False $State.safety.task_created "state.safety.task_created"
  Assert-False $State.safety.task_claimed "state.safety.task_claimed"
  Assert-False $State.safety.execution_started "state.safety.execution_started"
  Assert-False $State.safety.branch_created "state.safety.branch_created"
  Assert-False $State.safety.pr_created "state.safety.pr_created"
  Assert-False $State.safety.merge_performed "state.safety.merge_performed"
  Assert-False $State.safety.deploy_triggered "state.safety.deploy_triggered"
  Assert-False $State.safety.hermes_live_called "state.safety.hermes_live_called"
  Assert-False $State.safety.mcp_run_called "state.safety.mcp_run_called"
}

function Assert-OperatorTuiCandidateNoExecution($State, $Report) {
  Assert-False $State.execution_started "candidate_state.execution_started"
  Assert-False $State.task_created "candidate_state.task_created"
  Assert-False $State.task_claimed "candidate_state.task_claimed"
  Assert-False $State.branch_created "candidate_state.branch_created"
  Assert-False $State.pr_created "candidate_state.pr_created"
  Assert-False $State.token_printed "candidate_state.token_printed"

  Assert-False $Report.task_created "candidate_report.task_created"
  Assert-False $Report.task_claimed "candidate_report.task_claimed"
  Assert-False $Report.execution_started "candidate_report.execution_started"
  Assert-False $Report.branch_created "candidate_report.branch_created"
  Assert-False $Report.pr_created "candidate_report.pr_created"
  Assert-False $Report.merge_performed "candidate_report.merge_performed"
  Assert-False $Report.deploy_triggered "candidate_report.deploy_triggered"
  Assert-False $Report.worker_loop_started "candidate_report.worker_loop_started"
  Assert-False $Report.queue_runner_started "candidate_report.queue_runner_started"
  Assert-False $Report.hermes_live_called "candidate_report.hermes_live_called"
  Assert-False $Report.mcp_run_called "candidate_report.mcp_run_called"
  Assert-TokenPrintedFalse $Report
}
