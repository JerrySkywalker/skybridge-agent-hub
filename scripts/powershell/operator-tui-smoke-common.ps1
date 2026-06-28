$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-OperatorTuiSnapshot(
  [string]$Name,
  [ValidateSet("fixture", "local", "cloud", "local-cloud")]
  [string]$Mode = "fixture",
  [string]$OutputDir = ""
) {
  $cargo = Get-Command cargo -ErrorAction SilentlyContinue
  if (-not $cargo) {
    throw "cargo is required for operator TUI smokes."
  }

  & cargo check --manifest-path apps/operator-tui/Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw "operator TUI cargo check failed." }

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

function Assert-OperatorTuiShape($State, $Report, [string]$SnapshotText) {
  if ($State.schema -ne "skybridge.operator_tui_state.v1") { throw "Unexpected operator TUI state schema." }
  if ($Report.schema -ne "skybridge.operator_tui_report.v1") { throw "Unexpected operator TUI report schema." }
  if ($Report.state_schema -ne $State.schema) { throw "Operator TUI report/state schema mismatch." }
  Assert-True $State.read_only "state.read_only"
  Assert-True $State.safety.read_only "state.safety.read_only"

  $requiredPanels = @(
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer"
  )
  $panels = @($Report.panels_rendered | ForEach-Object { [string]$_ })
  foreach ($panel in $requiredPanels) {
    if ($panels -notcontains $panel) { throw "Missing panel: $panel" }
    if ($SnapshotText -notmatch [regex]::Escape($panel)) { throw "Snapshot text missing panel: $panel" }
  }

  $disabledActions = @($Report.disabled_actions | ForEach-Object { [string]$_.action })
  foreach ($action in @(
    "generate_candidate_fixture",
    "validate_candidate",
    "append_candidate",
    "preview_bounded_action",
    "start_one_goal",
    "safe_pause",
    "abort_terminate"
  )) {
    if ($disabledActions -notcontains $action) { throw "Disabled action missing: $action" }
  }

  $activeActions = @($Report.active_actions | ForEach-Object { [string]$_.action })
  foreach ($action in @("refresh_local_cloud_state", "copy_safe_summary", "quit")) {
    if ($activeActions -notcontains $action) { throw "Active action missing: $action" }
  }
  foreach ($action in $activeActions) {
    if ($action -notin @("refresh_local_cloud_state", "copy_safe_summary", "quit")) {
      throw "Unexpected active operator TUI action: $action"
    }
  }

  foreach ($entry in @($Report.disabled_actions)) {
    $reasons = @($entry.disabled_reasons | ForEach-Object { [string]$_ })
    foreach ($reason in @(
      "action_disabled_in_mg368b",
      "requires_later_reviewed_gate",
      "execution_apply_disabled",
      "mutation_not_allowed_in_read_only_monitor"
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
