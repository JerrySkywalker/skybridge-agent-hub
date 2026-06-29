$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$OperatorTuiReviewConfirmation = "I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION"
$OperatorTuiAppendConfirmation = "I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION"
$OperatorTuiStartConfirmation = "I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP"
$OperatorTuiPauseConfirmation = "I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON"
$OperatorTuiAbortConfirmation = "I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL"
$OperatorTuiCandidateOutputDir = ".agent/tmp/operator-tui/candidate-flow"
$OperatorTuiSingleStepOutputDir = ".agent/tmp/operator-tui/single-step"

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

function Initialize-OperatorTuiSingleStepCandidate {
  Invoke-OperatorTuiCandidateFlow `
    -Name "single-step-candidate" `
    -Actions @("generate", "validate", "review-approve", "append-preview", "append-apply-fixture") `
    -Reset `
    -ReviewConfirm $OperatorTuiReviewConfirmation `
    -AppendConfirm $OperatorTuiAppendConfirmation | Out-Null
}

function Invoke-OperatorTuiSingleStepFlow(
  [string]$Name,
  [string[]]$Actions,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiSingleStepOutputDir,
  [string]$StartConfirm = "",
  [string]$PauseConfirm = "",
  [string]$AbortConfirm = "",
  [string]$PauseReason = "",
  [string]$AbortReason = ""
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiSingleStepArtifacts -OutputDir $OutputDir }

  foreach ($action in $Actions) {
    $args = @(
      "--single-step",
      "--single-step-action",
      $action,
      "--single-step-mode",
      "fixture",
      "--snapshot",
      "--write-report",
      "--output-dir",
      $OutputDir
    )
    if (-not [string]::IsNullOrWhiteSpace($StartConfirm)) {
      $args += @("--start-confirm", $StartConfirm)
    }
    if (-not [string]::IsNullOrWhiteSpace($PauseConfirm)) {
      $args += @("--pause-confirm", $PauseConfirm)
    }
    if (-not [string]::IsNullOrWhiteSpace($AbortConfirm)) {
      $args += @("--abort-confirm", $AbortConfirm)
    }
    if (-not [string]::IsNullOrWhiteSpace($PauseReason)) {
      $args += @("--pause-reason", $PauseReason)
    }
    if (-not [string]::IsNullOrWhiteSpace($AbortReason)) {
      $args += @("--abort-reason", $AbortReason)
    }

    & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "operator TUI single-step action failed: $action" }
  }

  $snapshotPath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-snapshot.txt"
  $statePath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-report.md"
  $previewPath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-preview.json"
  $previewMarkdownPath = Join-Path $RepoRoot "$OutputDir/operator-tui-single-step-preview.md"

  foreach ($path in @($snapshotPath, $statePath, $reportPath, $reportMarkdownPath, $previewPath, $previewMarkdownPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI single-step artifact: $path" }
  }

  $snapshotText = Get-Content -Raw -LiteralPath $snapshotPath
  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $previewMarkdown = Get-Content -Raw -LiteralPath $previewMarkdownPath
  Assert-NoUnsafeText $snapshotText
  Assert-NoUnsafeText $reportMarkdown
  Assert-NoUnsafeText $previewMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $preview = Get-Content -Raw -LiteralPath $previewPath | ConvertFrom-Json

  Assert-OperatorTuiSingleStepShape -State $state -Report $report -SnapshotText $snapshotText
  Assert-OperatorTuiSingleStepNoLoop -State $state -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    snapshot_path = $snapshotPath
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    preview_path = $previewPath
    preview_markdown_path = $previewMarkdownPath
    snapshot_text = $snapshotText
    state = $state
    report = $report
    preview = $preview
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

function Clear-OperatorTuiSingleStepArtifacts([string]$OutputDir = $OperatorTuiSingleStepOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI single-step artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
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

function Assert-OperatorTuiSingleStepShape($State, $Report, [string]$SnapshotText) {
  if ($State.schema -ne "skybridge.operator_tui_single_step_state.v1") { throw "Unexpected single-step state schema." }
  if ($Report.schema -ne "skybridge.operator_tui_single_step_report.v1") { throw "Unexpected single-step report schema." }
  if ($Report.mode -ne "single-step-control") { throw "Single-step report must use single-step-control mode." }
  Assert-OperatorTuiPanels -Panels $Report.panels_rendered -SnapshotText $SnapshotText
  Assert-OperatorTuiActions -Report $Report
  Assert-True $Report.local_state_loaded "single_step.local_state_loaded"
  Assert-True $Report.cloud_state_loaded "single_step.cloud_state_loaded"
  Assert-True $Report.cloud_parity_shown "single_step.cloud_parity_shown"
  Assert-True $Report.candidate_appended "single_step.candidate_appended"
  if ([string]::IsNullOrWhiteSpace([string]$Report.appended_step_id)) { throw "single_step.appended_step_id missing." }
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
  if ($disabledActions.Count -gt 0) {
    throw "MG368D should not report disabled operator TUI actions: $($disabledActions -join ', ')"
  }

  $activeActions = @($Report.active_actions | ForEach-Object { [string]$_.action })
  $expectedActive = @(
    "refresh_local_cloud_state",
    "generate_candidate_fixture",
    "validate_candidate",
    "review_candidate",
    "append_candidate",
    "preview_bounded_action",
    "start_one_goal",
    "safe_pause",
    "abort_terminate",
    "copy_safe_summary",
    "quit"
  )
  foreach ($action in $expectedActive) {
    if ($activeActions -notcontains $action) { throw "Active action missing: $action" }
  }
  foreach ($action in $activeActions) {
    if ($action -notin $expectedActive) { throw "Unexpected active operator TUI action: $action" }
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

function Assert-OperatorTuiSingleStepNoLoop($State, $Report) {
  Assert-False $State.task_created "single_step_state.task_created"
  Assert-False $State.task_claimed "single_step_state.task_claimed"
  Assert-False $State.execution_started "single_step_state.execution_started"
  Assert-False $State.branch_created "single_step_state.branch_created"
  Assert-False $State.pr_created "single_step_state.pr_created"
  Assert-False $State.draft_pr_created "single_step_state.draft_pr_created"
  Assert-False $State.worker_loop_started "single_step_state.worker_loop_started"
  Assert-False $State.queue_runner_started "single_step_state.queue_runner_started"
  Assert-False $State.run_forever_started "single_step_state.run_forever_started"
  Assert-False $State.hermes_live_called "single_step_state.hermes_live_called"
  Assert-False $State.mcp_run_called "single_step_state.mcp_run_called"
  Assert-False $State.merge_performed "single_step_state.merge_performed"
  Assert-False $State.deploy_triggered "single_step_state.deploy_triggered"
  Assert-False $State.auto_merge_enabled "single_step_state.auto_merge_enabled"
  Assert-False $State.release_created "single_step_state.release_created"
  Assert-False $State.tag_created "single_step_state.tag_created"
  Assert-False $State.asset_uploaded "single_step_state.asset_uploaded"
  Assert-False $State.token_printed "single_step_state.token_printed"

  Assert-False $Report.task_created "single_step_report.task_created"
  Assert-False $Report.task_claimed "single_step_report.task_claimed"
  Assert-False $Report.execution_started "single_step_report.execution_started"
  Assert-False $Report.branch_created "single_step_report.branch_created"
  Assert-False $Report.pr_created "single_step_report.pr_created"
  Assert-False $Report.draft_pr_created "single_step_report.draft_pr_created"
  Assert-False $Report.merge_performed "single_step_report.merge_performed"
  Assert-False $Report.deploy_triggered "single_step_report.deploy_triggered"
  Assert-False $Report.worker_loop_started "single_step_report.worker_loop_started"
  Assert-False $Report.queue_runner_started "single_step_report.queue_runner_started"
  Assert-False $Report.run_forever_started "single_step_report.run_forever_started"
  Assert-False $Report.hermes_live_called "single_step_report.hermes_live_called"
  Assert-False $Report.mcp_run_called "single_step_report.mcp_run_called"
  Assert-False $Report.auto_merge_enabled "single_step_report.auto_merge_enabled"
  Assert-False $Report.release_created "single_step_report.release_created"
  Assert-False $Report.tag_created "single_step_report.tag_created"
  Assert-False $Report.asset_uploaded "single_step_report.asset_uploaded"
  Assert-TokenPrintedFalse $Report
}
