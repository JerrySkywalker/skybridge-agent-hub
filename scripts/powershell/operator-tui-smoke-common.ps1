$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-OperatorTuiSnapshot([string]$Name) {
  $cargo = Get-Command cargo -ErrorAction SilentlyContinue
  if (-not $cargo) {
    throw "cargo is required for operator TUI smokes."
  }

  & cargo check --manifest-path apps/operator-tui/Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw "operator TUI cargo check failed." }

  $outputDir = ".agent/tmp/operator-tui/$Name"
  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- --fixture --snapshot --write-report --output-dir $outputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI snapshot run failed." }

  $snapshotPath = Join-Path $RepoRoot "$outputDir/operator-tui-snapshot.txt"
  $statePath = Join-Path $RepoRoot "$outputDir/operator-tui-state.json"
  $reportPath = Join-Path $RepoRoot "$outputDir/operator-tui-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$outputDir/operator-tui-report.md"

  foreach ($path in @($snapshotPath, $statePath, $reportPath, $reportMarkdownPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI artifact: $path" }
  }

  $snapshotText = Get-Content -Raw -LiteralPath $snapshotPath
  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  Assert-NoUnsafeText $snapshotText
  Assert-NoUnsafeText $reportMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

  if ($state.schema -ne "skybridge.operator_tui_state.v1") { throw "Unexpected operator TUI state schema." }
  if ($report.schema -ne "skybridge.operator_tui_report.v1") { throw "Unexpected operator TUI report schema." }
  if ($report.state_schema -ne $state.schema) { throw "Operator TUI report/state schema mismatch." }

  $requiredPanels = @(
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer"
  )
  $panels = @($report.panels_rendered | ForEach-Object { [string]$_ })
  foreach ($panel in $requiredPanels) {
    if ($panels -notcontains $panel) { throw "Missing panel: $panel" }
    if ($snapshotText -notmatch [regex]::Escape($panel)) { throw "Snapshot text missing panel: $panel" }
  }

  $disabledActions = @($report.disabled_actions | ForEach-Object { [string]$_.action })
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

  $activeActions = @($report.active_actions | ForEach-Object { [string]$_.action })
  foreach ($action in @("refresh_fixture_state", "copy_safe_summary", "quit")) {
    if ($activeActions -notcontains $action) { throw "Active action missing: $action" }
  }

  foreach ($entry in @($report.disabled_actions)) {
    $reasons = @($entry.disabled_reasons | ForEach-Object { [string]$_ })
    foreach ($reason in @(
      "action_disabled_in_mg368a",
      "requires_later_reviewed_gate",
      "execution_apply_disabled",
      "mutation_not_allowed_in_fixture"
    )) {
      if ($reasons -notcontains $reason) { throw "Disabled action $($entry.action) missing reason: $reason" }
    }
  }

  Assert-False $report.mutation_attempted "mutation_attempted"
  Assert-False $report.append_attempted "append_attempted"
  Assert-False $report.approval_attempted "approval_attempted"
  Assert-False $report.task_created "task_created"
  Assert-False $report.task_claimed "task_claimed"
  Assert-False $report.execution_started "execution_started"
  Assert-False $report.branch_created "branch_created"
  Assert-False $report.pr_created "pr_created"
  Assert-False $report.merge_performed "merge_performed"
  Assert-False $report.deploy_triggered "deploy_triggered"
  Assert-False $report.worker_loop_started "worker_loop_started"
  Assert-False $report.queue_runner_started "queue_runner_started"
  Assert-False $report.hermes_live_called "hermes_live_called"
  Assert-False $report.mcp_run_called "mcp_run_called"
  Assert-TokenPrintedFalse $report

  Assert-False $state.safety.token_printed "state.safety.token_printed"
  Assert-False $state.safety.auto_merge_enabled "state.safety.auto_merge_enabled"
  Assert-False $state.safety.release_created "state.safety.release_created"
  Assert-False $state.safety.tag_created "state.safety.tag_created"
  Assert-False $state.safety.asset_uploaded "state.safety.asset_uploaded"
  Assert-False $state.safety.worker_loop_started "state.safety.worker_loop_started"
  Assert-False $state.safety.queue_runner_started "state.safety.queue_runner_started"
  Assert-False $state.safety.task_created "state.safety.task_created"
  Assert-False $state.safety.task_claimed "state.safety.task_claimed"
  Assert-False $state.safety.execution_started "state.safety.execution_started"
  Assert-False $state.safety.hermes_live_called "state.safety.hermes_live_called"
  Assert-False $state.safety.mcp_run_called "state.safety.mcp_run_called"

  [pscustomobject]@{
    output_dir = $outputDir
    snapshot_path = $snapshotPath
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    snapshot_text = $snapshotText
    state = $state
    report = $report
  }
}
