$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$OperatorTuiReviewConfirmation = "I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION"
$OperatorTuiAppendConfirmation = "I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION"
$OperatorTuiStartConfirmation = "I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP"
$OperatorTuiPauseConfirmation = "I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON"
$OperatorTuiAbortConfirmation = "I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL"
$OperatorTuiCandidateOutputDir = ".agent/tmp/operator-tui/candidate-flow"
$OperatorTuiSingleStepOutputDir = ".agent/tmp/operator-tui/single-step"
$OperatorTuiInteractiveOutputDir = ".agent/tmp/operator-tui/interactive-unblocker"
$OperatorTuiRuntimeOutputDir = ".agent/tmp/operator-tui/runtime-refactor"
$OperatorTuiLayoutOutputDir = ".agent/tmp/operator-tui/layout"
$OperatorTuiInputUxOutputDir = ".agent/tmp/operator-tui/input-ux"
$OperatorTuiManualReliabilityOutputDir = ".agent/tmp/operator-tui/manual-reliability"
$OperatorTuiUxYoloOutputDir = ".agent/tmp/operator-tui/ux-yolo"
$OperatorTuiMg369cOutputDir = ".agent/tmp/operator-tui/mg369c-yolo"

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

function Invoke-OperatorTuiInteractiveSimulation(
  [string]$Name,
  [ValidateSet("actions", "confirmation-reject", "reason-required", "candidate-dispatch", "single-step-dispatch", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiInteractiveOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiInteractiveArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --interactive-unblocker-smoke $Scenario `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI interactive simulation failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/interactive-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/interactive-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/interactive-report.md"
  $lastActionPath = Join-Path $RepoRoot "$OutputDir/last-action.json"
  $manualGatePath = Join-Path $RepoRoot "$OutputDir/manual-gate.md"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $lastActionPath, $manualGatePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI interactive artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $manualGateMarkdown = Get-Content -Raw -LiteralPath $manualGatePath
  Assert-NoUnsafeText $reportMarkdown
  Assert-NoUnsafeText $manualGateMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $lastAction = Get-Content -Raw -LiteralPath $lastActionPath | ConvertFrom-Json

  Assert-OperatorTuiInteractiveShape -State $state -Report $report -LastAction $lastAction
  Assert-OperatorTuiInteractiveNoRealExecution -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    last_action_path = $lastActionPath
    manual_gate_path = $manualGatePath
    state = $state
    report = $report
    last_action = $lastAction
  }
}

function Invoke-OperatorTuiRuntimeRefactorSimulation(
  [string]$Name,
  [ValidateSet("nonblocking", "command-status", "timeout", "stale-result", "one-command", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiRuntimeOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiRuntimeArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --runtime-refactor-smoke $Scenario `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI runtime refactor simulation failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/runtime-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/runtime-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/runtime-report.md"
  $historyPath = Join-Path $RepoRoot "$OutputDir/command-history.json"
  $timeoutPath = Join-Path $RepoRoot "$OutputDir/timeout-report.json"
  $stalePath = Join-Path $RepoRoot "$OutputDir/stale-result-report.json"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $historyPath, $timeoutPath, $stalePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI runtime artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  Assert-NoUnsafeText $reportMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $history = @(Get-Content -Raw -LiteralPath $historyPath | ConvertFrom-Json)
  $timeout = Get-Content -Raw -LiteralPath $timeoutPath | ConvertFrom-Json
  $stale = Get-Content -Raw -LiteralPath $stalePath | ConvertFrom-Json

  Assert-OperatorTuiRuntimeShape -State $state -Report $report -History $history -Timeout $timeout -Stale $stale
  Assert-OperatorTuiRuntimeNoRealExecution -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    history_path = $historyPath
    timeout_path = $timeoutPath
    stale_path = $stalePath
    state = $state
    report = $report
    history = $history
    timeout = $timeout
    stale = $stale
  }
}

function Invoke-OperatorTuiLayoutSmoke(
  [string]$Name,
  [ValidateSet("full", "compact", "tiny", "tabs", "actions-compact", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiLayoutOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiLayoutArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --layout-smoke $Scenario `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI layout smoke failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/layout-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/layout-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/layout-report.md"
  $fullSnapshotPath = Join-Path $RepoRoot "$OutputDir/full-snapshot.txt"
  $compactSnapshotPath = Join-Path $RepoRoot "$OutputDir/compact-snapshot.txt"
  $tinySnapshotPath = Join-Path $RepoRoot "$OutputDir/tiny-snapshot.txt"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $fullSnapshotPath, $compactSnapshotPath, $tinySnapshotPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI layout artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $fullSnapshot = Get-Content -Raw -LiteralPath $fullSnapshotPath
  $compactSnapshot = Get-Content -Raw -LiteralPath $compactSnapshotPath
  $tinySnapshot = Get-Content -Raw -LiteralPath $tinySnapshotPath
  foreach ($text in @($reportMarkdown, $fullSnapshot, $compactSnapshot, $tinySnapshot)) {
    Assert-NoUnsafeText $text
  }

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

  Assert-OperatorTuiLayoutShape -State $state -Report $report -FullSnapshot $fullSnapshot -CompactSnapshot $compactSnapshot -TinySnapshot $tinySnapshot
  Assert-OperatorTuiLayoutNoRealExecution -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    full_snapshot_path = $fullSnapshotPath
    compact_snapshot_path = $compactSnapshotPath
    tiny_snapshot_path = $tinySnapshotPath
    state = $state
    report = $report
    full_snapshot = $fullSnapshot
    compact_snapshot = $compactSnapshot
    tiny_snapshot = $tinySnapshot
  }
}

function Invoke-OperatorTuiInputUxSmoke(
  [string]$Name,
  [ValidateSet("confirmation-dialog", "confirmation-mismatch", "confirmation-clear", "reason-required", "reason-sanitization", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiInputUxOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiInputUxArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --input-ux-smoke $Scenario `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI input UX smoke failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/input-ux-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/input-ux-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/input-ux-report.md"
  $mismatchPath = Join-Path $RepoRoot "$OutputDir/confirmation-mismatch.json"
  $reasonPath = Join-Path $RepoRoot "$OutputDir/reason-sanitization.json"
  $confirmationSnapshotPath = Join-Path $RepoRoot "$OutputDir/confirmation-dialog-snapshot.txt"
  $reasonSnapshotPath = Join-Path $RepoRoot "$OutputDir/reason-dialog-snapshot.txt"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $mismatchPath, $reasonPath, $confirmationSnapshotPath, $reasonSnapshotPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI input UX artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $confirmationSnapshot = Get-Content -Raw -LiteralPath $confirmationSnapshotPath
  $reasonSnapshot = Get-Content -Raw -LiteralPath $reasonSnapshotPath
  foreach ($text in @($reportMarkdown, $confirmationSnapshot, $reasonSnapshot)) {
    Assert-NoUnsafeText $text
  }

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $mismatch = Get-Content -Raw -LiteralPath $mismatchPath | ConvertFrom-Json
  $reason = Get-Content -Raw -LiteralPath $reasonPath | ConvertFrom-Json

  Assert-OperatorTuiInputUxShape -State $state -Report $report -Mismatch $mismatch -Reason $reason -ConfirmationSnapshot $confirmationSnapshot -ReasonSnapshot $reasonSnapshot
  Assert-OperatorTuiInputUxNoRealExecution -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    mismatch_path = $mismatchPath
    reason_path = $reasonPath
    confirmation_snapshot_path = $confirmationSnapshotPath
    reason_snapshot_path = $reasonSnapshotPath
    state = $state
    report = $report
    mismatch = $mismatch
    reason = $reason
    confirmation_snapshot = $confirmationSnapshot
    reason_snapshot = $reasonSnapshot
  }
}

function Invoke-OperatorTuiManualReliabilitySmoke(
  [string]$Name,
  [ValidateSet("confirmation-diagnostics", "running-guard", "timeout-guidance", "guide", "tabs-recorded", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiManualReliabilityOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiManualReliabilityArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --manual-reliability-smoke $Scenario `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI manual reliability smoke failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/reliability-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/reliability-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/reliability-report.md"
  $diagnosticsPath = Join-Path $RepoRoot "$OutputDir/confirmation-diagnostics.json"
  $runningGuardPath = Join-Path $RepoRoot "$OutputDir/running-guard-report.json"
  $timeoutPath = Join-Path $RepoRoot "$OutputDir/manual-timeout-report.json"
  $guidePath = Join-Path $RepoRoot "$OutputDir/dry-run-guide-report.json"
  $tabHistoryPath = Join-Path $RepoRoot "$OutputDir/tab-layout-history.json"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $diagnosticsPath, $runningGuardPath, $timeoutPath, $guidePath, $tabHistoryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI manual reliability artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  Assert-NoUnsafeText $reportMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $diagnostics = Get-Content -Raw -LiteralPath $diagnosticsPath | ConvertFrom-Json
  $runningGuard = Get-Content -Raw -LiteralPath $runningGuardPath | ConvertFrom-Json
  $timeout = Get-Content -Raw -LiteralPath $timeoutPath | ConvertFrom-Json
  $guide = Get-Content -Raw -LiteralPath $guidePath | ConvertFrom-Json
  $tabHistory = Get-Content -Raw -LiteralPath $tabHistoryPath | ConvertFrom-Json

  Assert-OperatorTuiManualReliabilityShape `
    -State $state `
    -Report $report `
    -Diagnostics $diagnostics `
    -RunningGuard $runningGuard `
    -Timeout $timeout `
    -Guide $guide `
    -TabHistory $tabHistory
  Assert-OperatorTuiManualReliabilityNoRealExecution -Report $report

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    diagnostics_path = $diagnosticsPath
    running_guard_path = $runningGuardPath
    timeout_path = $timeoutPath
    guide_path = $guidePath
    tab_history_path = $tabHistoryPath
    state = $state
    report = $report
    diagnostics = $diagnostics
    running_guard = $runningGuard
    timeout = $timeout
    guide = $guide
    tab_history = $tabHistory
  }
}

function Invoke-OperatorTuiUxYoloSmoke(
  [string]$Name,
  [ValidateSet("simplified-guide", "bilingual", "yolo-fixture-only", "self-drive", "confirmation-buffer", "no-real-execution")]
  [string]$Scenario,
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiUxYoloOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiUxYoloArtifacts -OutputDir $OutputDir }

  $args = @(
    "--ux-yolo-smoke",
    $Scenario,
    "--yolo-fixture-only",
    "--output-dir",
    $OutputDir
  )
  if ($Scenario -eq "bilingual") {
    $args += @("--lang", "en")
  }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- @args | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI UX YOLO smoke failed: $Scenario" }

  $statePath = Join-Path $RepoRoot "$OutputDir/ux-yolo-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/ux-yolo-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/ux-yolo-report.md"
  $selfDrivePath = Join-Path $RepoRoot "$OutputDir/self-drive-report.json"
  $bilingualPath = Join-Path $RepoRoot "$OutputDir/bilingual-report.json"
  $confirmationPath = Join-Path $RepoRoot "$OutputDir/confirmation-buffer-report.json"
  $safetyPath = Join-Path $RepoRoot "$OutputDir/yolo-safety-report.json"
  $snapshotPath = Join-Path $RepoRoot "$OutputDir/simplified-guide-snapshot.txt"
  $zhSnapshotPath = Join-Path $RepoRoot "$OutputDir/simplified-guide-zh-snapshot.txt"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $selfDrivePath, $bilingualPath, $confirmationPath, $safetyPath, $snapshotPath, $zhSnapshotPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI UX YOLO artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  $snapshot = Get-Content -Raw -LiteralPath $snapshotPath
  $zhSnapshot = Get-Content -Raw -LiteralPath $zhSnapshotPath
  foreach ($text in @($reportMarkdown, $snapshot, $zhSnapshot)) {
    Assert-NoUnsafeText $text
  }

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $selfDrive = Get-Content -Raw -LiteralPath $selfDrivePath | ConvertFrom-Json
  $bilingual = Get-Content -Raw -LiteralPath $bilingualPath | ConvertFrom-Json
  $confirmation = Get-Content -Raw -LiteralPath $confirmationPath | ConvertFrom-Json
  $safety = Get-Content -Raw -LiteralPath $safetyPath | ConvertFrom-Json

  Assert-OperatorTuiUxYoloShape `
    -State $state `
    -Report $report `
    -SelfDrive $selfDrive `
    -Bilingual $bilingual `
    -Confirmation $confirmation `
    -Safety $safety `
    -Snapshot $snapshot `
    -ZhSnapshot $zhSnapshot
  Assert-OperatorTuiUxYoloNoRealExecution -Report $report -Safety $safety

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    self_drive_path = $selfDrivePath
    bilingual_path = $bilingualPath
    confirmation_path = $confirmationPath
    safety_path = $safetyPath
    snapshot_path = $snapshotPath
    zh_snapshot_path = $zhSnapshotPath
    state = $state
    report = $report
    self_drive = $selfDrive
    bilingual = $bilingual
    confirmation = $confirmation
    safety = $safety
    snapshot = $snapshot
    zh_snapshot = $zhSnapshot
  }
}

function Invoke-OperatorTuiMg369cDocsPrSimulation(
  [switch]$Reset,
  [string]$OutputDir = $OperatorTuiMg369cOutputDir
) {
  Invoke-OperatorTuiCargoCheck
  if ($Reset) { Clear-OperatorTuiUxYoloArtifacts -OutputDir $OutputDir }

  & cargo run --quiet --manifest-path apps/operator-tui/Cargo.toml -- `
    --local-cloud `
    --operator-guide `
    --yolo-fixture-only `
    --self-drive-dry-run `
    --simulate-docs-pr `
    --lang zh-CN `
    --runtime-timeout-ms 120000 `
    --output-dir $OutputDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "operator TUI MG369C docs PR simulation failed." }

  $statePath = Join-Path $RepoRoot "$OutputDir/mg369c-yolo-state.json"
  $reportPath = Join-Path $RepoRoot "$OutputDir/mg369c-yolo-report.json"
  $reportMarkdownPath = Join-Path $RepoRoot "$OutputDir/mg369c-yolo-report.md"
  $simulationPath = Join-Path $RepoRoot "$OutputDir/mg369c-docs-pr-simulation.json"
  $safetyPath = Join-Path $RepoRoot "$OutputDir/mg369c-safety-report.json"
  $historyPath = Join-Path $RepoRoot "$OutputDir/mg369c-action-history.json"
  $indexPath = Join-Path $RepoRoot "$OutputDir/mg369c-artifact-index.json"

  foreach ($path in @($statePath, $reportPath, $reportMarkdownPath, $simulationPath, $safetyPath, $historyPath, $indexPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing operator TUI MG369C artifact: $path" }
  }

  $reportMarkdown = Get-Content -Raw -LiteralPath $reportMarkdownPath
  Assert-NoUnsafeText $reportMarkdown

  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $simulation = Get-Content -Raw -LiteralPath $simulationPath | ConvertFrom-Json
  $safety = Get-Content -Raw -LiteralPath $safetyPath | ConvertFrom-Json
  $history = Get-Content -Raw -LiteralPath $historyPath | ConvertFrom-Json
  $index = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json

  Assert-OperatorTuiMg369cShape -State $state -Report $report -Simulation $simulation -Safety $safety -History $history -Index $index
  Assert-OperatorTuiMg369cNoRealPr -Report $report -Simulation $simulation -Safety $safety
  Assert-OperatorTuiMg369cNoRealExecution -Report $report -Safety $safety

  [pscustomobject]@{
    output_dir = $OutputDir
    state_path = $statePath
    report_path = $reportPath
    report_markdown_path = $reportMarkdownPath
    simulation_path = $simulationPath
    safety_path = $safetyPath
    history_path = $historyPath
    index_path = $indexPath
    state = $state
    report = $report
    simulation = $simulation
    safety = $safety
    history = $history
    index = $index
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

function Clear-OperatorTuiInteractiveArtifacts([string]$OutputDir = $OperatorTuiInteractiveOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))
  $slug = Get-OperatorTuiOutputSlug -OutputDir $OutputDir
  $hermesDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/hermes-planner-provider/$slug"))
  $appendDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/goal-append/$slug"))

  foreach ($path in @($operatorDir, $hermesDir, $appendDir)) {
    if (-not $path.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove non-temp operator TUI interactive artifact path: $path"
    }
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

function Clear-OperatorTuiRuntimeArtifacts([string]$OutputDir = $OperatorTuiRuntimeOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI runtime artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
  }
}

function Clear-OperatorTuiLayoutArtifacts([string]$OutputDir = $OperatorTuiLayoutOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI layout artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
  }
}

function Clear-OperatorTuiInputUxArtifacts([string]$OutputDir = $OperatorTuiInputUxOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI input UX artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
  }
}

function Clear-OperatorTuiManualReliabilityArtifacts([string]$OutputDir = $OperatorTuiManualReliabilityOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI manual reliability artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
  }
}

function Clear-OperatorTuiUxYoloArtifacts([string]$OutputDir = $OperatorTuiUxYoloOutputDir) {
  $tmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  $operatorDir = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))

  if (-not $operatorDir.StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp operator TUI UX YOLO artifact path: $operatorDir"
  }
  if (Test-Path -LiteralPath $operatorDir) {
    Remove-Item -LiteralPath $operatorDir -Recurse -Force
  }
}

function Get-OperatorTuiOutputSlug([string]$OutputDir) {
  $normalized = $OutputDir.Replace("\", "/")
  if ($normalized.TrimEnd("/") -eq ".agent/tmp/operator-tui/candidate-flow") {
    return "operator-tui-candidate-flow"
  }

  $builder = New-Object System.Text.StringBuilder
  foreach ($ch in $normalized.ToCharArray()) {
    $code = [int][char]$ch
    $isAsciiLetterOrDigit = (
      ($code -ge 48 -and $code -le 57) -or
      ($code -ge 65 -and $code -le 90) -or
      ($code -ge 97 -and $code -le 122)
    )
    if ($isAsciiLetterOrDigit -or $ch -eq '-') {
      [void]$builder.Append($ch)
    } else {
      [void]$builder.Append("_")
    }
  }
  $slug = $builder.ToString().Trim("_")
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "operator-tui-candidate-flow" }
  if ($slug.Length -gt 96) { $slug = $slug.Substring(0, 96) }
  $slug
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

function Assert-OperatorTuiInteractiveShape($State, $Report, $LastAction) {
  if ($Report.schema -ne "skybridge.operator_tui_interactive_unblocker_report.v1") {
    throw "Unexpected interactive unblocker report schema."
  }
  if ($Report.mode -ne "interactive-unblocker") { throw "Interactive report must use interactive-unblocker mode." }
  Assert-True $Report.interactive_loop_available "interactive_loop_available"
  Assert-True $Report.keyboard_actions_registered "keyboard_actions_registered"
  Assert-True $Report.confirmation_input_available "confirmation_input_available"
  Assert-True $Report.reason_input_available "reason_input_available"
  Assert-True $Report.sanitized_reason_enforced "sanitized_reason_enforced"
  Assert-True $Report.manual_gate_written "manual_gate_written"
  Assert-False $Report.token_printed "interactive token_printed"
  if ($LastAction.token_printed -ne $false) { throw "last_action token_printed must be false." }

  $keys = @($Report.keyboard_actions | ForEach-Object { [string]$_ })
  foreach ($key in @("r", "g", "v", "e", "a", "p", "s", "h", "x", "c", "q")) {
    if ($keys -notcontains $key) { throw "Interactive keyboard action missing: $key" }
  }

  $confirmations = @($Report.exact_confirmations_required | ForEach-Object { [string]$_ })
  foreach ($confirmation in @(
    $OperatorTuiReviewConfirmation,
    $OperatorTuiAppendConfirmation,
    $OperatorTuiStartConfirmation,
    $OperatorTuiPauseConfirmation,
    $OperatorTuiAbortConfirmation
  )) {
    if ($confirmations -notcontains $confirmation) { throw "Missing interactive confirmation requirement." }
  }

  $panels = @($Report.panels_rendered | ForEach-Object { [string]$_ })
  foreach ($panel in @("Header / Global Status", "Pipeline Timeline", "Current Object", "Action Menu", "Safety Footer")) {
    if ($panels -notcontains $panel) { throw "Interactive report missing panel: $panel" }
  }
}

function Assert-OperatorTuiRuntimeShape($State, $Report, $History, $Timeout, $Stale) {
  if ($Report.schema -ne "skybridge.operator_tui_runtime_refactor_report.v1") {
    throw "Unexpected runtime refactor report schema."
  }
  if ($Report.mode -ne "runtime-refactor") { throw "Runtime report must use runtime-refactor mode." }
  Assert-True $Report.ui_loop_nonblocking "ui_loop_nonblocking"
  Assert-True $Report.background_command_runner_available "background_command_runner_available"
  Assert-True $Report.command_request_model_available "command_request_model_available"
  Assert-True $Report.command_result_model_available "command_result_model_available"
  Assert-True $Report.view_model_available "view_model_available"
  Assert-True $Report.one_command_at_a_time_enforced "one_command_at_a_time_enforced"
  Assert-True $Report.command_timeout_enforced "command_timeout_enforced"
  Assert-True $Report.running_state_rendered "running_state_rendered"
  Assert-True $Report.fixture_safe_only "fixture_safe_only"
  Assert-False $Report.token_printed "runtime token_printed"
  Assert-False $State.safety_flags.token_printed "runtime state token_printed"
  if ([string]::IsNullOrWhiteSpace([string]$Report.last_command_status)) {
    throw "runtime last_command_status missing."
  }
  if ([int]$Report.command_history_count -lt 2) {
    throw "runtime command_history_count too low."
  }
  if (@($History).Count -ne [int]$Report.command_history_count) {
    throw "runtime command history count mismatch."
  }
  if ($Timeout.schema -ne "skybridge.operator_tui_runtime_timeout_report.v1") {
    throw "Unexpected timeout report schema."
  }
  if ($Stale.schema -ne "skybridge.operator_tui_runtime_stale_result_report.v1") {
    throw "Unexpected stale result report schema."
  }
  Assert-False $Timeout.token_printed "timeout token_printed"
  Assert-False $Stale.token_printed "stale token_printed"
}

function Assert-OperatorTuiLayoutShape($State, $Report, [string]$FullSnapshot, [string]$CompactSnapshot, [string]$TinySnapshot) {
  if ($State.schema -ne "skybridge.operator_tui_layout_state.v1") {
    throw "Unexpected operator TUI layout state schema."
  }
  if ($Report.schema -ne "skybridge.operator_tui_layout_report.v1") {
    throw "Unexpected operator TUI layout report schema."
  }
  if ($Report.mode -ne "layout-responsive") { throw "Layout report must use layout-responsive mode." }
  Assert-True $Report.full_layout_available "full_layout_available"
  Assert-True $Report.compact_layout_available "compact_layout_available"
  Assert-True $Report.tiny_layout_available "tiny_layout_available"
  Assert-True $Report.tab_model_available "tab_model_available"
  Assert-True $Report.small_window_supported "small_window_supported"
  Assert-True $Report.tiny_window_supported "tiny_window_supported"
  Assert-True $Report.terminal_too_small_message_available "terminal_too_small_message_available"
  Assert-True $Report.action_menu_compact_available "action_menu_compact_available"
  Assert-True $Report.runtime_status_visible "runtime_status_visible"
  Assert-True $Report.safety_status_visible "safety_status_visible"
  Assert-False $Report.token_printed "layout token_printed"
  Assert-False $State.token_printed "layout_state token_printed"

  $tabs = @($Report.tabs | ForEach-Object { [string]$_ })
  foreach ($tab in @("Overview", "Pipeline", "Candidate", "Single-step", "Actions", "Runtime", "Safety", "Artifacts")) {
    if ($tabs -notcontains $tab) { throw "Layout tab missing: $tab" }
    if ($FullSnapshot -notmatch [regex]::Escape($tab)) { throw "Full snapshot missing tab: $tab" }
  }

  foreach ($needle in @("layout=full", "Global Status", "Command / Safety Footer", "command_status", "token_printed=false")) {
    if ($FullSnapshot -notmatch [regex]::Escape($needle)) { throw "Full snapshot missing: $needle" }
  }
  foreach ($needle in @("mode=compact", "current tab only", "command_status", "token_printed=false")) {
    if ($CompactSnapshot -notmatch [regex]::Escape($needle)) { throw "Compact snapshot missing: $needle" }
  }
  foreach ($needle in @("terminal too small", "minimum recommended size", "command_status", "q quit", "token_printed=false")) {
    if ($TinySnapshot -notmatch [regex]::Escape($needle)) { throw "Tiny snapshot missing: $needle" }
  }

  $oldPanelNames = @(
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer"
  )
  $oldPanelHits = @($oldPanelNames | Where-Object { $CompactSnapshot -match [regex]::Escape($_) })
  if ($oldPanelHits.Count -ge 5) {
    throw "Compact layout rendered all old five panels at once."
  }
}

function Assert-OperatorTuiInputUxShape($State, $Report, $Mismatch, $Reason, [string]$ConfirmationSnapshot, [string]$ReasonSnapshot) {
  if ($State.schema -ne "skybridge.operator_tui_input_ux_state.v1") {
    throw "Unexpected operator TUI input UX state schema."
  }
  if ($Report.schema -ne "skybridge.operator_tui_input_ux_report.v1") {
    throw "Unexpected operator TUI input UX report schema."
  }
  if ($Report.mode -ne "input-ux") { throw "Input UX report must use input-ux mode." }
  if ($Mismatch.schema -ne "skybridge.operator_tui_confirmation_mismatch.v1") {
    throw "Unexpected confirmation mismatch schema."
  }
  if ($Reason.schema -ne "skybridge.operator_tui_reason_sanitization.v1") {
    throw "Unexpected reason sanitization schema."
  }

  Assert-True $Report.confirmation_dialog_available "confirmation_dialog_available"
  Assert-True $Report.required_confirmation_visible "required_confirmation_visible"
  Assert-True $Report.input_match_indicator_available "input_match_indicator_available"
  Assert-True $Report.mismatch_feedback_available "mismatch_feedback_available"
  Assert-True $Report.retry_or_cancel_available "retry_or_cancel_available"
  Assert-True $Report.reason_dialog_available "reason_dialog_available"
  Assert-True $Report.reason_required_enforced "reason_required_enforced"
  Assert-True $Report.sanitized_reason_preview_available "sanitized_reason_preview_available"
  Assert-True $Report.ctrl_u_clear_available "ctrl_u_clear_available"
  Assert-True $Report.esc_cancel_available "esc_cancel_available"
  Assert-True $Report.backspace_available "backspace_available"
  Assert-True $Report.enter_submit_available "enter_submit_available"
  Assert-True $Report.paste_friendly_input_available "paste_friendly_input_available"
  Assert-True $Report.artifact_paths_visible_after_action "artifact_paths_visible_after_action"
  Assert-True $Report.help_available "help_available"
  Assert-False $Report.token_printed "input UX token_printed"
  Assert-False $State.token_printed "input UX state token_printed"
  Assert-False $Mismatch.token_printed "confirmation mismatch token_printed"
  Assert-False $Reason.token_printed "reason sanitization token_printed"
  Assert-False $Reason.raw_reason_persisted "reason raw_reason_persisted"

  $confirmations = @($Report.exact_confirmations_required | ForEach-Object { [string]$_ })
  foreach ($confirmation in @(
    $OperatorTuiReviewConfirmation,
    $OperatorTuiAppendConfirmation,
    $OperatorTuiStartConfirmation,
    $OperatorTuiPauseConfirmation,
    $OperatorTuiAbortConfirmation
  )) {
    if ($confirmations -notcontains $confirmation) { throw "Missing input UX confirmation requirement." }
  }
  $snapshotHasARequiredConfirmation = $false
  foreach ($confirmation in $confirmations) {
    if ($ConfirmationSnapshot -match [regex]::Escape($confirmation)) {
      $snapshotHasARequiredConfirmation = $true
      break
    }
  }
  if (-not $snapshotHasARequiredConfirmation) {
    throw "Confirmation snapshot missing a required exact confirmation."
  }

  foreach ($needle in @("Confirmation required", "risk_class", "required_exact_confirmation", "current_input_length", "input_matches_exactly", "Enter submit", "Esc cancel", "Ctrl+U clear", "Backspace delete", "q is treated as input", "token_printed=false")) {
    if ($ConfirmationSnapshot -notmatch [regex]::Escape($needle)) { throw "Confirmation snapshot missing: $needle" }
  }
  foreach ($needle in @("Reason required", "sanitized_reason_preview", "sanitization_changed", "Enter accept reason", "Esc cancel", "Ctrl+U clear", "Backspace delete", "token_printed=false")) {
    if ($ReasonSnapshot -notmatch [regex]::Escape($needle)) { throw "Reason snapshot missing: $needle" }
  }
}

function Assert-OperatorTuiInputUxNoRealExecution($Report) {
  Assert-False $Report.real_task_execution_enabled "real_task_execution_enabled"
  Assert-False $Report.real_branch_creation_enabled "real_branch_creation_enabled"
  Assert-False $Report.real_pr_creation_enabled "real_pr_creation_enabled"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.run_forever_started "run_forever_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-False $Report.auto_merge_enabled "auto_merge_enabled"
  Assert-False $Report.release_created "release_created"
  Assert-False $Report.tag_created "tag_created"
  Assert-False $Report.asset_uploaded "asset_uploaded"
  Assert-TokenPrintedFalse $Report
}

function Assert-OperatorTuiManualReliabilityShape($State, $Report, $Diagnostics, $RunningGuard, $Timeout, $Guide, $TabHistory) {
  if ($State.schema -ne "skybridge.operator_tui_manual_reliability_state.v1") {
    throw "Unexpected operator TUI manual reliability state schema."
  }
  if ($Report.schema -ne "skybridge.operator_tui_manual_reliability_report.v1") {
    throw "Unexpected operator TUI manual reliability report schema."
  }
  if ($Report.mode -ne "manual-reliability-repair") { throw "Manual reliability report mode mismatch." }
  if ($Diagnostics.schema -ne "skybridge.operator_tui_confirmation_diagnostics.v1") {
    throw "Unexpected confirmation diagnostics schema."
  }
  if ($RunningGuard.schema -ne "skybridge.operator_tui_manual_reliability_running_guard.v1") {
    throw "Unexpected running guard schema."
  }
  if ($Timeout.schema -ne "skybridge.operator_tui_manual_reliability_timeout.v1") {
    throw "Unexpected manual timeout schema."
  }
  if ($Guide.schema -ne "skybridge.operator_tui_manual_reliability_guide.v1") {
    throw "Unexpected dry-run guide schema."
  }
  if ($TabHistory.schema -ne "skybridge.operator_tui_manual_reliability_tab_layout_history.v1") {
    throw "Unexpected tab layout history schema."
  }

  Assert-True $Report.confirmation_diagnostics_available "confirmation_diagnostics_available"
  Assert-True $Report.expected_confirmation_length_recorded "expected_confirmation_length_recorded"
  Assert-True $Report.actual_confirmation_length_recorded "actual_confirmation_length_recorded"
  Assert-True $Report.first_mismatch_index_recorded "first_mismatch_index_recorded"
  Assert-True $Report.hidden_character_detection_available "hidden_character_detection_available"
  Assert-True $Report.confirmation_retry_guidance_visible "confirmation_retry_guidance_visible"
  Assert-True $Report.confirmation_normalization_available "confirmation_normalization_available"
  Assert-False $Report.raw_input_persisted "raw_input_persisted"
  Assert-True $Report.running_guard_visible "running_guard_visible"
  Assert-True $Report.mutation_actions_blocked_while_running "mutation_actions_blocked_while_running"
  Assert-True $Report.command_already_running_feedback_visible "command_already_running_feedback_visible"
  Assert-True $Report.manual_timeout_guidance_visible "manual_timeout_guidance_visible"
  Assert-True $Report.timeout_enforced "timeout_enforced"
  Assert-True $Report.dry_run_guide_available "dry_run_guide_available"
  Assert-True $Report.dry_run_steps_listed "dry_run_steps_listed"
  Assert-True $Report.layout_modes_recorded "layout_modes_recorded"
  Assert-True $Report.tabs_visited_recorded "tabs_visited_recorded"
  Assert-True $Report.confirmation_dialog_seen_recorded "confirmation_dialog_seen_recorded"
  Assert-True $Report.reason_dialog_seen_recorded "reason_dialog_seen_recorded"
  Assert-False $Report.token_printed "manual reliability token_printed"

  if ([int]$Report.manual_timeout_ms -lt 120000) {
    throw "manual_timeout_ms should be at least 120000."
  }
  if ([int]$Diagnostics.expected_confirmation_length -le 0) {
    throw "Expected confirmation length was not recorded."
  }
  if ([int]$Diagnostics.actual_input_length -le 0) {
    throw "Actual confirmation input length was not recorded."
  }
  if ($null -eq $Diagnostics.first_mismatch_index) {
    throw "First mismatch index was not recorded."
  }
  Assert-True $Diagnostics.contains_cr_lf_tab "diagnostics contains_cr_lf_tab"
  Assert-True $Diagnostics.has_leading_or_trailing_whitespace "diagnostics has_leading_or_trailing_whitespace"
  Assert-False $Diagnostics.raw_input_persisted "diagnostics raw_input_persisted"
  Assert-False $Diagnostics.token_printed "diagnostics token_printed"
  if ([string]::IsNullOrWhiteSpace([string]$Diagnostics.retry_guidance)) {
    throw "Confirmation retry guidance missing."
  }

  Assert-True $RunningGuard.running_guard_visible "running guard visible"
  Assert-True $RunningGuard.elapsed_seconds_visible "running guard elapsed_seconds_visible"
  Assert-True $RunningGuard.expected_wait_behavior_visible "running guard expected_wait_behavior_visible"
  Assert-True $RunningGuard.mutation_actions_blocked_while_running "running guard mutation blocked"
  Assert-True $RunningGuard.command_already_running_feedback_visible "running guard feedback visible"
  Assert-False $RunningGuard.token_printed "running guard token_printed"

  if ([int]$Timeout.manual_timeout_ms -lt 120000) { throw "Manual timeout report timeout too low." }
  Assert-True $Timeout.timeout_enforced "timeout enforced"
  Assert-True $Timeout.manual_timeout_guidance_visible "timeout guidance visible"
  Assert-True $Timeout.smoke_remains_bounded "smoke remains bounded"
  Assert-True $Timeout.no_unbounded_wait "no unbounded wait"
  Assert-True $Timeout.blocker_recorded_on_timeout "blocker recorded on timeout"
  Assert-False $Timeout.token_printed "timeout token_printed"

  Assert-True $Guide.dry_run_guide_available "dry_run_guide_available"
  Assert-True $Guide.guide_does_not_auto_execute "guide_does_not_auto_execute"
  Assert-True $Guide.command_running_visible "guide command_running_visible"
  Assert-True $Guide.wait_guidance_visible "guide wait_guidance_visible"
  Assert-True $Guide.required_confirmation_visible "guide required_confirmation_visible"
  Assert-True $Guide.reason_text_suggestions_visible "guide reason_text_suggestions_visible"
  Assert-True $Guide.completed_or_blocked_status_visible "guide completed_or_blocked_status_visible"
  if (@($Guide.steps).Count -ne 11) { throw "Expected 11 manual dry-run guide steps." }
  Assert-False $Guide.token_printed "guide token_printed"

  $modes = @($TabHistory.layout_modes_observed | ForEach-Object { [string]$_ })
  foreach ($mode in @("full", "compact", "tiny")) {
    if ($modes -notcontains $mode) { throw "Missing observed layout mode: $mode" }
  }
  $tabs = @($TabHistory.tabs_visited | ForEach-Object { [string]$_ })
  foreach ($tab in @("Overview", "Pipeline", "Candidate", "Single-step", "Actions", "Runtime", "Safety", "Artifacts")) {
    if ($tabs -notcontains $tab) { throw "Missing visited tab: $tab" }
  }
  Assert-True $TabHistory.help_opened "help_opened"
  Assert-True $TabHistory.actions_tab_visited "actions_tab_visited"
  Assert-True $TabHistory.runtime_tab_visited "runtime_tab_visited"
  Assert-True $TabHistory.safety_tab_visited "safety_tab_visited"
  Assert-True $TabHistory.confirmation_dialog_seen "confirmation_dialog_seen"
  Assert-True $TabHistory.reason_dialog_seen "reason_dialog_seen"
  Assert-False $TabHistory.token_printed "tab history token_printed"
  Assert-False $State.token_printed "manual reliability state token_printed"
}

function Assert-OperatorTuiManualReliabilityNoRealExecution($Report) {
  Assert-False $Report.real_task_execution_enabled "real_task_execution_enabled"
  Assert-False $Report.real_branch_creation_enabled "real_branch_creation_enabled"
  Assert-False $Report.real_pr_creation_enabled "real_pr_creation_enabled"
  Assert-False $Report.task_created "task_created"
  Assert-False $Report.task_claimed "task_claimed"
  Assert-False $Report.execution_started "execution_started"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.run_forever_started "run_forever_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-False $Report.auto_merge_enabled "auto_merge_enabled"
  Assert-False $Report.release_created "release_created"
  Assert-False $Report.tag_created "tag_created"
  Assert-False $Report.asset_uploaded "asset_uploaded"
  Assert-TokenPrintedFalse $Report
}

function Assert-OperatorTuiUxYoloShape($State, $Report, $SelfDrive, $Bilingual, $Confirmation, $Safety, [string]$Snapshot, [string]$ZhSnapshot) {
  if ($State.schema -ne "skybridge.operator_tui_ux_yolo_state.v1") {
    throw "Unexpected operator TUI UX YOLO state schema."
  }
  if ($Report.schema -ne "skybridge.operator_tui_ux_yolo_report.v1") {
    throw "Unexpected operator TUI UX YOLO report schema."
  }
  if ($Report.mode -ne "ux-yolo") { throw "UX YOLO report mode mismatch." }
  if ($SelfDrive.schema -ne "skybridge.operator_tui_self_drive_report.v1") {
    throw "Unexpected self-drive report schema."
  }
  if ($Bilingual.schema -ne "skybridge.operator_tui_bilingual_report.v1") {
    throw "Unexpected bilingual report schema."
  }
  if ($Confirmation.schema -ne "skybridge.operator_tui_confirmation_buffer_report.v1") {
    throw "Unexpected confirmation buffer report schema."
  }
  if ($Safety.schema -ne "skybridge.operator_tui_yolo_safety_report.v1") {
    throw "Unexpected YOLO safety report schema."
  }

  Assert-True $Report.simplified_guide_available "simplified_guide_available"
  Assert-True $Report.simplified_guide_default_for_manual_dry_run "simplified_guide_default_for_manual_dry_run"
  Assert-True $Report.bilingual_ui_available "bilingual_ui_available"
  Assert-True $Report.language_toggle_available "language_toggle_available"
  Assert-True $Report.zh_cn_translations_available "zh_cn_translations_available"
  Assert-True $Report.exact_confirmations_untranslated "exact_confirmations_untranslated"
  Assert-True $Report.yolo_fixture_only_available "yolo_fixture_only_available"
  Assert-True $Report.yolo_skips_exact_confirmations_only_in_fixture_mode "yolo_skips_exact_confirmations_only_in_fixture_mode"
  Assert-True $Report.yolo_real_execution_blocked "yolo_real_execution_blocked"
  Assert-True $Report.yolo_branch_pr_blocked "yolo_branch_pr_blocked"
  Assert-True $Report.yolo_queue_worker_blocked "yolo_queue_worker_blocked"
  Assert-True $Report.self_drive_available "self_drive_available"
  Assert-True $Report.self_drive_requires_fixture_only "self_drive_requires_fixture_only"
  Assert-True $Report.confirmation_buffer_starts_empty "confirmation_buffer_starts_empty"
  Assert-True $Report.action_hotkey_not_inserted_into_confirmation "action_hotkey_not_inserted_into_confirmation"
  Assert-True $Report.duplicate_paste_detection_available "duplicate_paste_detection_available"
  Assert-False $Report.raw_input_persisted "raw_input_persisted"
  Assert-False $Report.token_printed "ux yolo token_printed"
  Assert-False $State.token_printed "ux yolo state token_printed"
  Assert-False $SelfDrive.token_printed "self-drive token_printed"
  Assert-False $Bilingual.token_printed "bilingual token_printed"
  Assert-False $Confirmation.token_printed "confirmation buffer token_printed"
  Assert-False $Safety.token_printed "yolo safety token_printed"

  $languages = @($Report.available_languages | ForEach-Object { [string]$_ })
  foreach ($language in @("en", "zh-CN")) {
    if ($languages -notcontains $language) { throw "Missing language: $language" }
  }

  foreach ($exactConfirmation in @(
    $OperatorTuiReviewConfirmation,
    $OperatorTuiAppendConfirmation,
    $OperatorTuiStartConfirmation,
    $OperatorTuiPauseConfirmation,
    $OperatorTuiAbortConfirmation
  )) {
    if ($ZhSnapshot -notmatch [regex]::Escape($exactConfirmation)) {
      throw "zh-CN simplified guide translated or omitted exact confirmation: $exactConfirmation"
    }
  }

  foreach ($needle in @("Current step", "Next action", "Command status", "Safe to continue", "Expected result", "token_printed=false")) {
    if ($Snapshot -notmatch [regex]::Escape($needle)) { throw "Simplified guide snapshot missing: $needle" }
  }
  foreach ($needle in @("当前步骤", "下一步", "命令状态", "可以继续", "预期结果", "不会真实执行", "token_printed=false")) {
    if ($ZhSnapshot -notmatch [regex]::Escape($needle)) { throw "zh-CN simplified guide snapshot missing: $needle" }
  }

  Assert-True $Bilingual.bilingual_ui_available "bilingual bilingual_ui_available"
  Assert-True $Bilingual.language_toggle_available "bilingual language_toggle_available"
  Assert-True $Bilingual.zh_cn_translations_available "bilingual zh_cn_translations_available"
  Assert-True $Bilingual.exact_confirmations_untranslated "bilingual exact_confirmations_untranslated"
  Assert-True $SelfDrive.self_drive_available "self_drive_available"
  Assert-True $SelfDrive.self_drive_requires_fixture_only "self_drive_requires_fixture_only"
  Assert-True $SelfDrive.used_same_action_routing "used_same_action_routing"
  Assert-True $SelfDrive.waited_for_commands_to_finish "waited_for_commands_to_finish"
  Assert-True $SelfDrive.running_guard_evidence_recorded "running_guard_evidence_recorded"
  Assert-True $SelfDrive.no_real_execution_safety_flags_recorded "no_real_execution_safety_flags_recorded"
  Assert-True $Confirmation.confirmation_buffer_starts_empty "confirmation_buffer_starts_empty"
  Assert-True $Confirmation.action_hotkey_not_inserted_into_confirmation "action_hotkey_not_inserted_into_confirmation"
  Assert-True $Confirmation.ctrl_u_resets_length_zero "ctrl_u_resets_length_zero"
  Assert-True $Confirmation.esc_cancels_and_clears_buffer "esc_cancels_and_clears_buffer"
  Assert-True $Confirmation.successful_submit_clears_buffer "successful_submit_clears_buffer"
  Assert-True $Confirmation.mismatch_preserves_diagnostics "mismatch_preserves_diagnostics"
  Assert-True $Confirmation.paste_exact_once_has_expected_length "paste_exact_once_has_expected_length"
  Assert-True $Confirmation.duplicate_paste_detection_available "duplicate_paste_detection_available"
  Assert-True $Confirmation.likely_duplicate_paste "likely_duplicate_paste"
  Assert-False $Confirmation.raw_input_persisted "confirmation raw_input_persisted"
}

function Assert-OperatorTuiUxYoloNoRealExecution($Report, $Safety) {
  foreach ($name in @(
    "real_task_execution_enabled",
    "real_branch_creation_enabled",
    "real_pr_creation_enabled",
    "task_created",
    "task_claimed",
    "execution_started",
    "worker_loop_started",
    "queue_runner_started",
    "run_forever_started",
    "hermes_live_called",
    "mcp_run_called",
    "auto_merge_enabled",
    "release_created",
    "tag_created",
    "asset_uploaded"
  )) {
    Assert-False $Report.$name "ux_yolo_report.$name"
    Assert-False $Safety.$name "yolo_safety.$name"
  }
  Assert-True $Report.yolo_real_execution_blocked "report yolo_real_execution_blocked"
  Assert-True $Report.yolo_branch_pr_blocked "report yolo_branch_pr_blocked"
  Assert-True $Report.yolo_queue_worker_blocked "report yolo_queue_worker_blocked"
  Assert-True $Safety.yolo_real_execution_blocked "safety yolo_real_execution_blocked"
  Assert-True $Safety.yolo_branch_pr_blocked "safety yolo_branch_pr_blocked"
  Assert-True $Safety.yolo_queue_worker_blocked "safety yolo_queue_worker_blocked"
  Assert-TokenPrintedFalse $Report
  Assert-TokenPrintedFalse $Safety
}

function Assert-OperatorTuiMg369cShape($State, $Report, $Simulation, $Safety, $History, $Index) {
  if ($State.schema -ne "skybridge.operator_tui_mg369c_yolo_docs_pr_simulation_state.v1") {
    throw "Unexpected MG369C state schema."
  }
  if ($Report.schema -ne "skybridge.operator_tui_mg369c_yolo_docs_pr_simulation.v1") {
    throw "Unexpected MG369C report schema."
  }
  if ($Report.mode -ne "mg369c-yolo-docs-pr-simulation") {
    throw "Unexpected MG369C report mode."
  }
  if ($Simulation.schema -ne "skybridge.operator_tui_mg369c_docs_pr_simulation.v1") {
    throw "Unexpected MG369C simulation schema."
  }
  if ($Safety.schema -ne "skybridge.operator_tui_mg369c_yolo_safety_report.v1") {
    throw "Unexpected MG369C safety schema."
  }
  if ($History.schema -ne "skybridge.operator_tui_mg369c_yolo_action_history.v1") {
    throw "Unexpected MG369C action history schema."
  }
  if ($Index.schema -ne "skybridge.operator_tui_mg369c_yolo_artifact_index.v1") {
    throw "Unexpected MG369C artifact index schema."
  }

  Assert-True $Report.self_drive_used "self_drive_used"
  Assert-True $Report.yolo_fixture_only "yolo_fixture_only"
  Assert-True $Report.docs_only_pr_simulation_used "docs_only_pr_simulation_used"
  Assert-True $Report.simulated_docs_pr_completed "simulated_docs_pr_completed"
  Assert-True $Report.simulated_changed_files_docs_only "simulated_changed_files_docs_only"
  Assert-False $Report.manual_verification_performed "manual_verification_performed"
  Assert-True $Report.does_not_claim_human_validation "does_not_claim_human_validation"
  Assert-False $Report.raw_input_persisted "raw_input_persisted"
  Assert-TokenPrintedFalse $Report
  Assert-TokenPrintedFalse $Simulation
  Assert-TokenPrintedFalse $Safety
  Assert-TokenPrintedFalse $History
  Assert-TokenPrintedFalse $Index

  if ([string]::IsNullOrWhiteSpace([string]$Report.simulated_branch_name)) {
    throw "Missing simulated_branch_name."
  }
  if ([string]::IsNullOrWhiteSpace([string]$Report.simulated_pr_title)) {
    throw "Missing simulated_pr_title."
  }
  if ([string]::IsNullOrWhiteSpace([string]$Report.simulated_review_gate)) {
    throw "Missing simulated_review_gate."
  }
  $changedFiles = @($Report.simulated_changed_files | ForEach-Object { [string]$_ })
  if ($changedFiles.Count -lt 1) { throw "Missing simulated changed files." }
  foreach ($file in $changedFiles) {
    if ($file -notlike "docs/*") { throw "Simulated changed file is not docs-only: $file" }
  }
  $ciChecks = @($Report.simulated_ci_checks | ForEach-Object { [string]$_ })
  foreach ($check in @("Project check", "Docker build server", "Docker build web")) {
    if ($ciChecks -notcontains $check) { throw "Missing simulated CI check: $check" }
  }
  $states = @($Simulation.lifecycle_states | ForEach-Object { [string]$_ })
  foreach ($state in @(
    "not_started",
    "docs_change_planned",
    "branch_name_reserved_simulated",
    "docs_patch_prepared_simulated",
    "draft_pr_metadata_prepared_simulated",
    "ci_plan_attached_simulated",
    "review_gate_pending_simulated",
    "merge_not_allowed_simulated",
    "completed_simulation"
  )) {
    if ($states -notcontains $state) { throw "Missing MG369C simulated state: $state" }
  }
  if (@($History.self_drive_step_history).Count -lt 8) {
    throw "MG369C self-drive action history incomplete."
  }
  if (@($Index.artifacts).Count -lt 7) {
    throw "MG369C artifact index incomplete."
  }
}

function Assert-OperatorTuiMg369cNoRealPr($Report, $Simulation, $Safety) {
  foreach ($name in @(
    "TUI_created_branch",
    "TUI_created_PR",
    "git_push_called",
    "gh_pr_create_called",
    "github_api_called",
    "simulated_merge_allowed",
    "simulated_auto_merge_allowed",
    "simulated_release_allowed",
    "simulated_tag_allowed",
    "simulated_asset_upload_allowed"
  )) {
    Assert-False $Report.$name "mg369c_report.$name"
  }

  foreach ($name in @(
    "TUI_created_branch",
    "TUI_created_PR",
    "git_push_called",
    "gh_pr_create_called",
    "github_api_called",
    "simulated_merge_allowed",
    "simulated_auto_merge_allowed",
    "simulated_release_allowed",
    "simulated_tag_allowed",
    "simulated_asset_upload_allowed"
  )) {
    Assert-False $Simulation.$name "mg369c_simulation.$name"
  }

  foreach ($name in @("TUI_created_branch", "TUI_created_PR", "git_push_called", "gh_pr_create_called", "github_api_called")) {
    Assert-False $Safety.$name "mg369c_safety.$name"
  }
}

function Assert-OperatorTuiMg369cNoRealExecution($Report, $Safety) {
  foreach ($name in @(
    "real_task_execution_enabled",
    "real_branch_creation_enabled",
    "real_pr_creation_enabled",
    "task_created",
    "task_claimed",
    "execution_started",
    "worker_loop_started",
    "queue_runner_started",
    "run_forever_started",
    "hermes_live_called",
    "mcp_run_called",
    "auto_merge_enabled",
    "release_created",
    "tag_created",
    "asset_uploaded"
  )) {
    Assert-False $Report.$name "mg369c_report.$name"
    Assert-False $Safety.$name "mg369c_safety.$name"
  }
  Assert-False $Report.raw_input_persisted "mg369c_report.raw_input_persisted"
  Assert-False $Safety.raw_input_persisted "mg369c_safety.raw_input_persisted"
  Assert-TokenPrintedFalse $Report
  Assert-TokenPrintedFalse $Safety
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

function Assert-OperatorTuiInteractiveNoRealExecution($Report) {
  Assert-False $Report.real_task_execution_enabled "real_task_execution_enabled"
  Assert-False $Report.real_branch_creation_enabled "real_branch_creation_enabled"
  Assert-False $Report.real_pr_creation_enabled "real_pr_creation_enabled"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.run_forever_started "run_forever_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-False $Report.auto_merge_enabled "auto_merge_enabled"
  Assert-False $Report.release_created "release_created"
  Assert-False $Report.tag_created "tag_created"
  Assert-False $Report.asset_uploaded "asset_uploaded"
  Assert-TokenPrintedFalse $Report
}

function Assert-OperatorTuiRuntimeNoRealExecution($Report) {
  Assert-False $Report.real_task_execution_enabled "real_task_execution_enabled"
  Assert-False $Report.real_branch_creation_enabled "real_branch_creation_enabled"
  Assert-False $Report.real_pr_creation_enabled "real_pr_creation_enabled"
  Assert-False $Report.task_created "task_created"
  Assert-False $Report.task_claimed "task_claimed"
  Assert-False $Report.execution_started "execution_started"
  Assert-False $Report.branch_created "branch_created"
  Assert-False $Report.pr_created "pr_created"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.run_forever_started "run_forever_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-False $Report.auto_merge_enabled "auto_merge_enabled"
  Assert-False $Report.release_created "release_created"
  Assert-False $Report.tag_created "tag_created"
  Assert-False $Report.asset_uploaded "asset_uploaded"
  Assert-TokenPrintedFalse $Report
}

function Assert-OperatorTuiLayoutNoRealExecution($Report) {
  Assert-False $Report.real_task_execution_enabled "real_task_execution_enabled"
  Assert-False $Report.real_branch_creation_enabled "real_branch_creation_enabled"
  Assert-False $Report.real_pr_creation_enabled "real_pr_creation_enabled"
  Assert-False $Report.queue_runner_started "queue_runner_started"
  Assert-False $Report.worker_loop_started "worker_loop_started"
  Assert-False $Report.run_forever_started "run_forever_started"
  Assert-False $Report.hermes_live_called "hermes_live_called"
  Assert-False $Report.mcp_run_called "mcp_run_called"
  Assert-False $Report.auto_merge_enabled "auto_merge_enabled"
  Assert-False $Report.release_created "release_created"
  Assert-False $Report.tag_created "tag_created"
  Assert-False $Report.asset_uploaded "asset_uploaded"
  Assert-TokenPrintedFalse $Report
}
