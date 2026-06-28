[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$requiredDocs = @(
  "docs/product/BOOTSTRAP_ALPHA_PRODUCT_FLOW.md",
  "docs/product/CLIENT_WORKER_SERVER_ARCHITECTURE.md",
  "docs/product/NATURAL_LANGUAGE_TO_TASK_FLOW.md",
  "docs/product/TASK_TEMPLATE_MODEL.md",
  "docs/product/CHAT_TO_TASK_DRAFT_PLANNER.md",
  "docs/product/TASK_TEMPLATE_REGISTRY.md",
  "docs/product/DRAFT_REVIEW_AND_SUBMIT.md",
  "docs/product/WORKER_TEMPLATE_RUNNER_V1.md",
  "docs/product/LIVE_WORKER_ONE_SAFE_TEMPLATE_TASK.md",
  "docs/product/MATLAB_EXPERIMENT_GOLDEN_TRIAL.md",
  "docs/product/MATLAB_STARTUP_DIAGNOSTICS_AND_RECOVERY.md",
  "docs/product/MATLAB_LOCAL_RUNTIME_REPAIR.md",
  "docs/product/MATLAB_GOLDEN_RECOVERY_SUCCESS.md",
  "docs/product/CODEX_ANALYSIS_REPORT_GOLDEN_TRIAL.md",
  "docs/product/CODEX_ARTIFACT_PERSISTENCE_RECOVERY.md",
  "docs/product/CODEX_NATIVE_REPORT_VALIDATION_SUCCESS.md",
  "docs/release/BOOTSTRAP_ALPHA_SCOPE.md",
  "docs/release/BOOTSTRAP_ALPHA_ROADMAP.md",
  "docs/release/WINDOWS_WORKER_INSTALL_BOOTSTRAP_ALPHA.md",
  "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md",
  "docs/release/BOOTSTRAP_ALPHA_RC_RUNBOOK.md",
  "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md",
  "docs/release/BOOTSTRAP_ALPHA_TAG_PLAN.md",
  "docs/release/BOOTSTRAP_ALPHA_RC1_HANDOFF.md",
  "docs/desktop/DESKTOP_PACKAGING_READINESS.md",
  "docs/desktop/DESKTOP_INSTALLER_RC_PLAN.md",
  "docs/desktop/DESKTOP_INSTALLER_STAGING.md",
  "docs/desktop/DESKTOP_INSTALLER_POST_RELEASE_SMOKE.md",
  "docs/desktop/DESKTOP_LAUNCH_CONSOLE_EXIT_FIX.md",
  "docs/orchestrator/TOOL_PROVIDER_CONTRACT.md",
  "docs/orchestrator/SINGLE_GOAL_LOOP_CONTROLLER.md",
  "docs/orchestrator/MULTI_STEP_STATIC_GOAL_LOOP.md",
  "docs/orchestrator/LOCAL_CODEX_GOAL_GENERATOR.md",
  "docs/dev/CODEX_STOP_HOOK_HYGIENE.md"
)

$requiredScripts = @{
  operator_report = "scripts/powershell/smoke-operator-report.ps1"
  review_gate = "scripts/powershell/smoke-review-gate.ps1"
  cloud_parity = "scripts/powershell/skybridge-cloud-parity-check.ps1"
  worker_service_status = "scripts/powershell/skybridge-worker-service-status.ps1"
  worker_service_doctor = "scripts/powershell/skybridge-worker-service-doctor.ps1"
  worker_service_install_preview = "scripts/powershell/skybridge-worker-service-install-preview.ps1"
  worker_service_repair_preview = "scripts/powershell/skybridge-worker-service-repair-preview.ps1"
  worker_service_install = "scripts/powershell/skybridge-worker-service-install.ps1"
  worker_service_repair = "scripts/powershell/skybridge-worker-service-repair.ps1"
  worker_heartbeat_pairing_drill = "scripts/powershell/skybridge-worker-heartbeat-pairing-drill.ps1"
  worker_identity = "scripts/powershell/skybridge-worker-identity.ps1"
  worker_live_heartbeat = "scripts/powershell/skybridge-worker-live-heartbeat.ps1"
  chat_to_task_draft = "scripts/powershell/skybridge-chat-to-task-draft.ps1"
  task_template_registry = "scripts/powershell/skybridge-task-template-registry.ps1"
  draft_submit = "scripts/powershell/skybridge-draft-submit.ps1"
  worker_template_runner = "scripts/powershell/skybridge-worker-template-runner.ps1"
  live_safe_task_pilot = "scripts/powershell/skybridge-live-safe-task-pilot.ps1"
  matlab_parameter_sweep_runner = "scripts/powershell/skybridge-matlab-parameter-sweep-runner.ps1"
  live_matlab_golden_trial = "scripts/powershell/skybridge-live-matlab-golden-trial.ps1"
  matlab_doctor = "scripts/powershell/skybridge-matlab-doctor.ps1"
  matlab_local_config = "scripts/powershell/skybridge-matlab-local-config.ps1"
  live_matlab_golden_recovery = "scripts/powershell/skybridge-live-matlab-golden-recovery.ps1"
  live_matlab_golden_success = "scripts/powershell/skybridge-live-matlab-golden-success.ps1"
  codex_analysis_report_runner = "scripts/powershell/skybridge-codex-analysis-report-runner.ps1"
  live_codex_analysis_report_trial = "scripts/powershell/skybridge-live-codex-analysis-report-trial.ps1"
  live_codex_analysis_report_recovery = "scripts/powershell/skybridge-live-codex-analysis-report-recovery.ps1"
  live_codex_native_report = "scripts/powershell/skybridge-live-codex-analysis-report-native-success.ps1"
  bootstrap_alpha_rc_gate = "scripts/powershell/skybridge-bootstrap-alpha-rc-gate.ps1"
  bootstrap_alpha_rc_report_smoke = "scripts/powershell/smoke-bootstrap-alpha-rc-report.ps1"
  bootstrap_alpha_tag_preview_smoke = "scripts/powershell/smoke-bootstrap-alpha-tag-preview.ps1"
  bootstrap_alpha_rc1_handoff = "scripts/powershell/skybridge-bootstrap-alpha-rc1-handoff.ps1"
  bootstrap_alpha_rc1_handoff_smoke = "scripts/powershell/smoke-bootstrap-alpha-rc1-handoff.ps1"
  codex_stop_hook_hygiene_smoke = "scripts/powershell/smoke-codex-stop-hook-hygiene.ps1"
  bootstrap_alpha_rc1_tag_check_smoke = "scripts/powershell/smoke-bootstrap-alpha-rc1-tag-check.ps1"
  desktop_packaging_readiness = "scripts/powershell/skybridge-desktop-packaging-readiness.ps1"
  desktop_packaging_readiness_smoke = "scripts/powershell/smoke-desktop-packaging-readiness.ps1"
  desktop_packaging_safety_smoke = "scripts/powershell/smoke-desktop-packaging-safety.ps1"
  desktop_installer_rc_plan_smoke = "scripts/powershell/smoke-desktop-installer-rc-plan.ps1"
  desktop_installer_staging = "scripts/powershell/skybridge-desktop-installer-staging.ps1"
  desktop_installer_staging_preview_smoke = "scripts/powershell/smoke-desktop-installer-staging-preview.ps1"
  desktop_installer_staging_checksum_smoke = "scripts/powershell/smoke-desktop-installer-staging-checksum.ps1"
  desktop_installer_staging_no_upload_smoke = "scripts/powershell/smoke-desktop-installer-staging-no-upload.ps1"
  desktop_installer_post_release_smoke = "scripts/powershell/skybridge-desktop-installer-post-release-smoke.ps1"
  desktop_installer_post_release_checksum_smoke = "scripts/powershell/smoke-desktop-installer-post-release-checksum-fixture.ps1"
  desktop_installer_post_release_no_silent_smoke = "scripts/powershell/smoke-desktop-installer-post-release-no-silent-install.ps1"
  desktop_installer_post_release_safety_smoke = "scripts/powershell/smoke-desktop-installer-post-release-safety.ps1"
  desktop_launch_diagnostics = "scripts/powershell/skybridge-desktop-launch-diagnostics.ps1"
  desktop_launch_diagnostics_smoke = "scripts/powershell/smoke-desktop-launch-diagnostics-status.ps1"
  desktop_launch_no_console_smoke = "scripts/powershell/smoke-desktop-launch-no-console-fixture.ps1"
  desktop_launch_no_fatal_missing_config_smoke = "scripts/powershell/smoke-desktop-launch-no-fatal-missing-config.ps1"
  desktop_launch_safety_smoke = "scripts/powershell/smoke-desktop-launch-safety.ps1"
  tool_provider = "scripts/powershell/skybridge-tool-provider.ps1"
  manual_tool_provider_check = "scripts/powershell/manual-tool-provider-check.ps1"
  tool_provider_status_smoke = "scripts/powershell/smoke-tool-provider-status.ps1"
  tool_provider_inventory_smoke = "scripts/powershell/smoke-tool-provider-inventory-fixture.ps1"
  tool_provider_direct_smoke = "scripts/powershell/smoke-tool-provider-direct-fixture.ps1"
  tool_provider_hermes_smoke = "scripts/powershell/smoke-tool-provider-hermes-detect-fixture.ps1"
  tool_provider_mcp_disabled_smoke = "scripts/powershell/smoke-tool-provider-mcp-disabled.ps1"
  tool_provider_report_smoke = "scripts/powershell/smoke-tool-provider-report.ps1"
  tool_provider_no_execution_smoke = "scripts/powershell/smoke-tool-provider-no-execution.ps1"
  manual_tool_provider_check_smoke = "scripts/powershell/smoke-manual-tool-provider-check-fixture.ps1"
  single_goal_loop = "scripts/powershell/skybridge-goal-loop.ps1"
  manual_single_goal_loop_test = "scripts/powershell/manual-single-goal-loop-test.ps1"
  single_goal_loop_status_smoke = "scripts/powershell/smoke-single-goal-loop-status.ps1"
  single_goal_loop_preview_smoke = "scripts/powershell/smoke-single-goal-loop-preview.ps1"
  single_goal_loop_fixture_smoke = "scripts/powershell/smoke-single-goal-loop-fixture.ps1"
  single_goal_loop_reject_no_confirm_smoke = "scripts/powershell/smoke-single-goal-loop-reject-no-confirm.ps1"
  single_goal_loop_reject_unsafe_smoke = "scripts/powershell/smoke-single-goal-loop-reject-unsafe.ps1"
  single_goal_loop_evidence_smoke = "scripts/powershell/smoke-single-goal-loop-evidence.ps1"
  single_goal_loop_no_worker_loop_smoke = "scripts/powershell/smoke-single-goal-loop-no-worker-loop.ps1"
  manual_single_goal_loop_fixture_smoke = "scripts/powershell/smoke-manual-single-goal-loop-fixture.ps1"
  multi_goal_loop = "scripts/powershell/skybridge-multi-goal-loop.ps1"
  manual_multi_goal_loop_test = "scripts/powershell/manual-multi-goal-loop-test.ps1"
  multi_goal_loop_status_smoke = "scripts/powershell/smoke-multi-goal-loop-status.ps1"
  multi_goal_loop_preview_smoke = "scripts/powershell/smoke-multi-goal-loop-preview.ps1"
  multi_goal_loop_fixture_step1_smoke = "scripts/powershell/smoke-multi-goal-loop-fixture-step1.ps1"
  multi_goal_loop_fixture_all_smoke = "scripts/powershell/smoke-multi-goal-loop-fixture-all.ps1"
  multi_goal_loop_reject_no_confirm_smoke = "scripts/powershell/smoke-multi-goal-loop-reject-no-confirm.ps1"
  multi_goal_loop_dependency_block_smoke = "scripts/powershell/smoke-multi-goal-loop-dependency-block.ps1"
  multi_goal_loop_reject_unsafe_smoke = "scripts/powershell/smoke-multi-goal-loop-reject-unsafe.ps1"
  multi_goal_loop_evidence_smoke = "scripts/powershell/smoke-multi-goal-loop-evidence.ps1"
  multi_goal_loop_no_worker_loop_smoke = "scripts/powershell/smoke-multi-goal-loop-no-worker-loop.ps1"
  manual_multi_goal_loop_fixture_smoke = "scripts/powershell/smoke-manual-multi-goal-loop-fixture.ps1"
  local_goal_generator = "scripts/powershell/skybridge-local-goal-generator.ps1"
  manual_local_goal_generate_test = "scripts/powershell/manual-local-goal-generate-test.ps1"
  local_goal_generator_status_smoke = "scripts/powershell/smoke-local-goal-generator-status.ps1"
  local_goal_generator_preview_smoke = "scripts/powershell/smoke-local-goal-generator-preview.ps1"
  local_goal_generator_fixture_smoke = "scripts/powershell/smoke-local-goal-generator-fixture.ps1"
  local_goal_generator_validate_smoke = "scripts/powershell/smoke-local-goal-generator-validate.ps1"
  local_goal_generator_reject_no_confirm_smoke = "scripts/powershell/smoke-local-goal-generator-reject-no-confirm.ps1"
  local_goal_generator_reject_unsafe_smoke = "scripts/powershell/smoke-local-goal-generator-reject-unsafe.ps1"
  local_goal_generator_no_import_smoke = "scripts/powershell/smoke-local-goal-generator-no-import.ps1"
  local_goal_generator_no_execution_smoke = "scripts/powershell/smoke-local-goal-generator-no-execution.ps1"
  manual_local_goal_generator_fixture_smoke = "scripts/powershell/smoke-manual-local-goal-generator-fixture.ps1"
}

$componentPaths = @{
  desktop_app = "apps/desktop"
  server_app = "apps/server"
}

$workerPathCandidates = @(
  "scripts/powershell/skybridge-worker-service-status.ps1",
  "scripts/powershell/skybridge-worker-service-doctor.ps1",
  "scripts/powershell/skybridge-worker-service.ps1",
  "scripts/powershell/skybridge-worker-status.ps1",
  "scripts/powershell/smoke-worker-service-contract.ps1",
  "scripts/powershell/smoke-worker-status.ps1"
)

function Test-RelativePath {
  param([string]$RelativePath, [switch]$Leaf, [switch]$Container)
  $path = Join-Path $RepoRoot $RelativePath
  if ($Leaf) { return (Test-Path -LiteralPath $path -PathType Leaf) }
  if ($Container) { return (Test-Path -LiteralPath $path -PathType Container) }
  return (Test-Path -LiteralPath $path)
}

function Read-JsonPackage {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "package.json not found."
  }
  Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
}

$docResults = foreach ($doc in $requiredDocs) {
  [pscustomobject]@{
    path = $doc
    exists = (Test-RelativePath -RelativePath $doc -Leaf)
  }
}

$scriptResults = foreach ($name in $requiredScripts.Keys) {
  [pscustomobject]@{
    name = $name
    path = $requiredScripts[$name]
    exists = (Test-RelativePath -RelativePath $requiredScripts[$name] -Leaf)
  }
}

$componentResults = foreach ($name in $componentPaths.Keys) {
  [pscustomobject]@{
    name = $name
    path = $componentPaths[$name]
    exists = (Test-RelativePath -RelativePath $componentPaths[$name] -Container)
  }
}

$workerResults = foreach ($candidate in $workerPathCandidates) {
  [pscustomobject]@{
    path = $candidate
    exists = (Test-RelativePath -RelativePath $candidate -Leaf)
  }
}

$package = Read-JsonPackage
$scripts = $package.scripts
$requiredPackageScripts = @(
  "check",
  "smoke:operator-report",
  "smoke:review-gate",
  "smoke:self-bootstrap-converge",
  "smoke:bootstrap-alpha-acceptance",
  "smoke:worker-service-status",
  "smoke:worker-service-doctor",
  "smoke:desktop-worker-service-manager",
  "smoke:worker-service-install-preview",
  "smoke:worker-service-install-apply-fixture",
  "smoke:worker-service-repair-preview",
  "smoke:worker-heartbeat-pairing-fixture",
  "smoke:desktop-worker-install-flow",
  "smoke:worker-identity-preview",
  "smoke:worker-identity-apply-fixture",
  "smoke:worker-live-heartbeat-preview",
  "smoke:worker-live-heartbeat-fixture",
  "smoke:desktop-worker-identity-heartbeat",
  "smoke:chat-to-task-draft",
  "smoke:desktop-chat-to-task",
  "smoke:chat-to-task-matlab-example",
  "smoke:task-template-registry",
  "smoke:task-template-registry-matlab",
  "smoke:desktop-task-template-registry",
  "smoke:draft-submit-preview",
  "smoke:draft-submit-server",
  "smoke:draft-submit-matlab-campaign",
  "smoke:desktop-draft-review-submit",
  "smoke:worker-template-runner-preview",
  "smoke:worker-template-runner-apply-one-fixture",
  "smoke:worker-template-runner-reject-unsafe",
  "smoke:desktop-worker-template-runner",
  "smoke:live-safe-task-pilot-preview",
  "smoke:live-safe-task-pilot-fixture",
  "smoke:live-safe-task-pilot-reject-unsafe",
  "smoke:desktop-live-safe-task-pilot",
  "smoke:matlab-golden-runner-preview",
  "smoke:matlab-golden-runner-fixture",
  "smoke:matlab-golden-trial-preview",
  "smoke:matlab-golden-trial-reject-unsafe",
  "smoke:desktop-matlab-golden-trial",
  "smoke:matlab-local-config-preview",
  "smoke:matlab-local-config-fixture",
  "smoke:matlab-doctor-classification",
  "smoke:matlab-doctor-fallback-fixture",
  "smoke:desktop-matlab-runtime-repair",
  "smoke:matlab-doctor-preview",
  "smoke:matlab-doctor-fixture",
  "smoke:matlab-recovery-preview",
  "smoke:matlab-recovery-fixture",
  "smoke:matlab-failed-evidence-accuracy",
  "smoke:matlab-golden-success-preview",
  "smoke:matlab-golden-success-fixture",
  "smoke:matlab-golden-success-reject-unsafe",
  "smoke:matlab-success-evidence-validation",
  "smoke:desktop-matlab-golden-success",
  "smoke:codex-analysis-report-preview",
  "smoke:codex-analysis-report-fixture",
  "smoke:codex-analysis-report-reject-unsafe",
  "smoke:codex-analysis-report-evidence-validation",
  "smoke:desktop-codex-analysis-report",
  "smoke:codex-artifact-path-contract",
  "smoke:codex-artifact-fallback-writer",
  "smoke:codex-artifact-evidence-validation",
  "smoke:codex-analysis-report-recovery-preview",
  "smoke:codex-analysis-report-recovery-fixture",
  "smoke:codex-analysis-report-recovery-reject-unsafe",
  "smoke:desktop-codex-artifact-recovery",
  "smoke:codex-native-report-validation",
  "smoke:codex-native-report-fixture",
  "smoke:codex-native-report-fallback-not-used-fixture",
  "smoke:codex-native-report-reject-unsafe",
  "smoke:codex-native-report-orchestrator-preview",
  "smoke:desktop-codex-native-report",
  "smoke:desktop-matlab-recovery",
  "smoke:bootstrap-alpha-rc-gate",
  "smoke:bootstrap-alpha-rc-gate-local",
  "smoke:bootstrap-alpha-rc-report",
  "smoke:bootstrap-alpha-disabled-features",
  "smoke:bootstrap-alpha-tag-preview",
  "smoke:bootstrap-alpha-rc1-handoff",
  "smoke:bootstrap-alpha-rc1-handoff-local",
  "smoke:bootstrap-alpha-rc1-handoff-report",
  "smoke:codex-stop-hook-hygiene",
  "smoke:bootstrap-alpha-rc1-tag-check",
  "smoke:desktop-packaging-readiness",
  "smoke:desktop-packaging-inventory",
  "smoke:desktop-packaging-build-preview",
  "smoke:desktop-packaging-report",
  "smoke:desktop-packaging-safety",
  "smoke:desktop-installer-rc-plan",
  "smoke:desktop-installer-staging-preview",
  "smoke:desktop-installer-staging-artifact-check",
  "smoke:desktop-installer-staging-checksum",
  "smoke:desktop-installer-staging-report",
  "smoke:desktop-installer-staging-safety",
  "smoke:desktop-installer-staging-no-upload",
  "smoke:desktop-installer-post-release-status",
  "smoke:desktop-installer-post-release-checksum-fixture",
  "smoke:desktop-installer-post-release-checklist",
  "smoke:desktop-installer-post-release-report",
  "smoke:desktop-installer-post-release-no-silent-install",
  "smoke:desktop-installer-post-release-safety",
  "smoke:desktop-launch-diagnostics-status",
  "smoke:desktop-launch-diagnostics-inspect",
  "smoke:desktop-launch-no-console-fixture",
  "smoke:desktop-launch-no-fatal-missing-config",
  "smoke:desktop-launch-safety",
  "smoke:desktop-launch-report",
  "smoke:tool-provider-status",
  "smoke:tool-provider-inventory-fixture",
  "smoke:tool-provider-direct-fixture",
  "smoke:tool-provider-hermes-detect-fixture",
  "smoke:tool-provider-mcp-disabled",
  "smoke:tool-provider-report",
  "smoke:tool-provider-no-execution",
  "smoke:manual-tool-provider-check-fixture",
  "smoke:single-goal-loop-status",
  "smoke:single-goal-loop-preview",
  "smoke:single-goal-loop-fixture",
  "smoke:single-goal-loop-reject-no-confirm",
  "smoke:single-goal-loop-reject-unsafe",
  "smoke:single-goal-loop-evidence",
  "smoke:single-goal-loop-no-worker-loop",
  "smoke:manual-single-goal-loop-fixture",
  "smoke:multi-goal-loop-status",
  "smoke:multi-goal-loop-preview",
  "smoke:multi-goal-loop-fixture-step1",
  "smoke:multi-goal-loop-fixture-all",
  "smoke:multi-goal-loop-reject-no-confirm",
  "smoke:multi-goal-loop-dependency-block",
  "smoke:multi-goal-loop-reject-unsafe",
  "smoke:multi-goal-loop-evidence",
  "smoke:multi-goal-loop-no-worker-loop",
  "smoke:manual-multi-goal-loop-fixture",
  "smoke:local-goal-generator-status",
  "smoke:local-goal-generator-preview",
  "smoke:local-goal-generator-fixture",
  "smoke:local-goal-generator-validate",
  "smoke:local-goal-generator-reject-no-confirm",
  "smoke:local-goal-generator-reject-unsafe",
  "smoke:local-goal-generator-no-import",
  "smoke:local-goal-generator-no-execution",
  "smoke:manual-local-goal-generator-fixture"
)
$packageScriptResults = foreach ($scriptName in $requiredPackageScripts) {
  [pscustomobject]@{
    name = $scriptName
    exists = [bool]($scripts.PSObject.Properties.Name -contains $scriptName)
  }
}

$docSecretFindings = @()
foreach ($doc in $requiredDocs) {
  $path = Join-Path $RepoRoot $doc
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $text = Get-Content -Raw -LiteralPath $path
    try {
      Assert-NoUnsafeText $text
    } catch {
      $docSecretFindings += [pscustomobject]@{
        path = $doc
        issue = "unsafe_marker_detected"
      }
    }
  }
}

$missingDocs = @($docResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
$missingScripts = @($scriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$missingComponents = @($componentResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$missingPackageScripts = @($packageScriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$workerSupportPresent = [bool](@($workerResults | Where-Object { $_.exists }).Count -gt 0)

$desktopWorkerServiceManagerPresent = $false
$desktopChatToTaskPanelPresent = $false
$desktopTaskTemplateRegistryPanelPresent = $false
$desktopDraftReviewSubmitPanelPresent = $false
$desktopWorkerTemplateRunnerPanelPresent = $false
$desktopLiveSafeTaskPilotPresent = $false
$desktopMatlabGoldenTrialPresent = $false
$desktopMatlabRecoveryPresent = $false
$desktopMatlabRuntimeRepairPresent = $false
$desktopMatlabGoldenSuccessPresent = $false
$desktopCodexAnalysisReportPresent = $false
$desktopCodexArtifactRecoveryPresent = $false
$desktopCodexNativeReportPresent = $false
$desktopWorkerInstallFlowPresent = $false
$desktopWorkerIdentityHeartbeatPresent = $false
$desktopSourcePath = Join-Path $RepoRoot "apps/desktop/src/main.tsx"
if (Test-Path -LiteralPath $desktopSourcePath -PathType Leaf) {
  $desktopSource = Get-Content -Raw -LiteralPath $desktopSourcePath
  $desktopWorkerServiceManagerPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Worker Setup") -and
    $desktopSource -match [regex]::Escape("LocalWorkerServiceStatus") -and
    $desktopSource -match [regex]::Escape("claim_enabled=false") -and
    $desktopSource -match [regex]::Escape("execute_enabled=false") -and
    $desktopSource -match [regex]::Escape("worker_loop_started=false; token_printed=false")
  )
  $desktopWorkerInstallFlowPresent = (
    $desktopSource -match [regex]::Escape("MG331 identity and live heartbeat apply are PowerShell exact-confirmation only") -and
    $desktopSource -match [regex]::Escape("Install apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Repair apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Heartbeat pairing preview") -and
    $desktopSource -match [regex]::Escape("Heartbeat apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Cloud worker registered") -and
    $desktopSource -match [regex]::Escape("template_runner_enabled=false; worker_loop_started=false; token_printed=false")
  )
  $desktopWorkerIdentityHeartbeatPresent = (
    $desktopSource -match [regex]::Escape("Worker identity status") -and
    $desktopSource -match [regex]::Escape("Identity setup preview") -and
    $desktopSource -match [regex]::Escape("Identity apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Live heartbeat preview") -and
    $desktopSource -match [regex]::Escape("Live heartbeat last result") -and
    $desktopSource -match [regex]::Escape("Live heartbeat apply unavailable in Desktop")
  )
  $desktopChatToTaskPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Chat-to-Task") -and
    $desktopSource -match [regex]::Escape("skybridge.task_draft_preview.v1") -and
    $desktopSource -match [regex]::Escape("task_created=false") -and
    $desktopSource -match [regex]::Escape("execution_started=false; codex_run_called=false; matlab_run_called=false; token_printed=false") -and
    $desktopSource -match [regex]::Escape("Draft Review + Submit")
  )
  $desktopTaskTemplateRegistryPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Task Templates") -and
    $desktopSource -match [regex]::Escape("skybridge.task_template_registry.v1") -and
    $desktopSource -match [regex]::Escape("execution_supported=false") -and
    $desktopSource -match [regex]::Escape("task_creation_supported=false; campaign_creation_supported=false; claim_supported=false") -and
    $desktopSource -match [regex]::Escape("codex_run_supported=false; matlab_run_supported=false; arbitrary_shell_enabled=false; token_printed=false")
  )
  $desktopDraftReviewSubmitPanelPresent = (
    $desktopSource -match [regex]::Escape("Draft Review + Submit") -and
    $desktopSource -match [regex]::Escape("Submit preview") -and
    $desktopSource -match [regex]::Escape("Confirm submit") -and
    $desktopSource -match [regex]::Escape("DRAFT_SUBMIT_CONFIRMATION_TEXT") -and
    $desktopSource -match [regex]::Escape("submitPreview.schema") -and
    $desktopSource -match [regex]::Escape("submitResult.schema") -and
    $desktopSource -match [regex]::Escape("Run with Worker (MG329 future work)") -and
    $desktopSource -match [regex]::Escape("claim_created=false") -and
    $desktopSource -match [regex]::Escape("execution_started=false") -and
    $desktopSource -match [regex]::Escape("worker_loop_started=false") -and
    $desktopSource -match [regex]::Escape("token_printed=false")
  )
  $desktopWorkerTemplateRunnerPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Worker Runner Preview") -and
    $desktopSource -match [regex]::Escape("BootstrapAlphaWorkerTemplateRunnerPanel") -and
    $desktopSource -match [regex]::Escape("skybridge.worker_template_runner_preview.v1") -and
    $desktopSource -match [regex]::Escape("Desktop preview-only") -and
    $desktopSource -match [regex]::Escape("MaxTasks=1; claim via PowerShell exact confirmation only") -and
    $desktopSource -match [regex]::Escape("codex_run_called=false; matlab_run_called=false; arbitrary_shell_enabled=false; worker_loop_started=false; token_printed=false")
  )
  $desktopLiveSafeTaskPilotPresent = (
    $desktopSource -match [regex]::Escape("MG332 live pilot is PowerShell-only for task live-safe-template-task-332-001") -and
    $desktopSource -match [regex]::Escape("MG332 target task id") -and
    $desktopSource -match [regex]::Escape("MG332 task claimed count") -and
    $desktopSource -match [regex]::Escape("MG332 live apply unavailable in Desktop")
  )
  $desktopMatlabGoldenTrialPresent = (
    $desktopSource -match [regex]::Escape("MG333 MATLAB golden trial is PowerShell-only for task live-matlab-golden-task-333-001") -and
    $desktopSource -match [regex]::Escape("MG333 target task id") -and
    $desktopSource -match [regex]::Escape("MG333 parameter grid") -and
    $desktopSource -match [regex]::Escape("MG333 raw_stdout_included") -and
    $desktopSource -match [regex]::Escape("MG333 MATLAB apply unavailable in Desktop")
  )
  $desktopMatlabRecoveryPresent = (
    $desktopSource -match [regex]::Escape("MG334 MATLAB recovery is PowerShell-only for task live-matlab-golden-task-334-001") -and
    $desktopSource -match [regex]::Escape("MG334 MATLAB doctor status") -and
    $desktopSource -match [regex]::Escape("MG334 doctor failure category") -and
    $desktopSource -match [regex]::Escape("MG334 recovery task id") -and
    $desktopSource -match [regex]::Escape("MG334 recovery existing outputs") -and
    $desktopSource -match [regex]::Escape("MG334 recovery expected outputs missing") -and
    $desktopSource -match [regex]::Escape("MG334 recovery apply unavailable in Desktop")
  )
  $desktopMatlabRuntimeRepairPresent = (
    $desktopSource -match [regex]::Escape("MG335 MATLAB runtime repair status") -and
    $desktopSource -match [regex]::Escape("MG335 configured MATLAB executable") -and
    $desktopSource -match [regex]::Escape("MG335 fallback_supported") -and
    $desktopSource -match [regex]::Escape("MG335 recommended next action") -and
    $desktopSource -match [regex]::Escape("MG335 MATLAB local config preview") -and
    $desktopSource -match [regex]::Escape("MG335 MATLAB local config apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("MG335 MATLAB doctor apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("MG335 task claim disabled")
  )
  $desktopMatlabGoldenSuccessPresent = (
    $desktopSource -match [regex]::Escape("MG336 MATLAB golden success is PowerShell-only for task live-matlab-golden-task-336-001") -and
    $desktopSource -match [regex]::Escape("MG336 MATLAB Golden Success status") -and
    $desktopSource -match [regex]::Escape("MG336 success task id") -and
    $desktopSource -match [regex]::Escape("MG336 doctor precondition") -and
    $desktopSource -match [regex]::Escape("MG336 manifest exists") -and
    $desktopSource -match [regex]::Escape("MG336 summary exists") -and
    $desktopSource -match [regex]::Escape("MG336 metrics exists") -and
    $desktopSource -match [regex]::Escape("MG336 success apply unavailable in Desktop")
  )
  $desktopCodexAnalysisReportPresent = (
    $desktopSource -match [regex]::Escape("MG337 Codex analysis report is PowerShell-only for task live-codex-analysis-report-task-337-001") -and
    $desktopSource -match [regex]::Escape("MG337 Codex Analysis Report status") -and
    $desktopSource -match [regex]::Escape("MG337 target task id") -and
    $desktopSource -match [regex]::Escape("MG337 input manifest exists") -and
    $desktopSource -match [regex]::Escape("MG337 output report path") -and
    $desktopSource -match [regex]::Escape("MG337 report exists") -and
    $desktopSource -match [regex]::Escape("MG337 Codex apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("PR creation disabled for MG337")
  )
  $desktopCodexArtifactRecoveryPresent = (
    $desktopSource -match [regex]::Escape("MG338 Codex artifact recovery is PowerShell-only for task live-codex-analysis-report-task-338-001") -and
    $desktopSource -match [regex]::Escape("MG338 Codex Artifact Recovery status") -and
    $desktopSource -match [regex]::Escape("MG338 recovery task id") -and
    $desktopSource -match [regex]::Escape("MG338 input manifest exists") -and
    $desktopSource -match [regex]::Escape("MG338 output report path") -and
    $desktopSource -match [regex]::Escape("MG338 report exists") -and
    $desktopSource -match [regex]::Escape("MG338 report_size_bytes") -and
    $desktopSource -match [regex]::Escape("MG338 fallback_report_used") -and
    $desktopSource -match [regex]::Escape("MG338 validation_status") -and
    $desktopSource -match [regex]::Escape("MG338 Codex recovery apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("PR creation disabled for MG338")
  )
  $desktopCodexNativeReportPresent = (
    $desktopSource -match [regex]::Escape("MG339 Codex native report is PowerShell-only for task live-codex-analysis-report-task-339-001") -and
    $desktopSource -match [regex]::Escape("MG339 Codex Native Report status") -and
    $desktopSource -match [regex]::Escape("MG339 native task id") -and
    $desktopSource -match [regex]::Escape("MG339 input manifest exists") -and
    $desktopSource -match [regex]::Escape("MG339 report path") -and
    $desktopSource -match [regex]::Escape("MG339 report exists") -and
    $desktopSource -match [regex]::Escape("MG339 report_size_bytes") -and
    $desktopSource -match [regex]::Escape("MG339 final_report_source") -and
    $desktopSource -match [regex]::Escape("MG339 fallback_report_used") -and
    $desktopSource -match [regex]::Escape("MG339 native_report_valid") -and
    $desktopSource -match [regex]::Escape("MG339 native validation failure category") -and
    $desktopSource -match [regex]::Escape("MG339 Codex native apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("PR creation disabled for MG339")
  )
}

$workerStatusContract = $null
$workerStatusContractOk = $false
$workerStatusError = $null
$chatToTaskContract = $null
$chatToTaskContractOk = $false
$chatToTaskError = $null
$taskTemplateRegistryContract = $null
$taskTemplateRegistryContractOk = $false
$taskTemplateRegistryError = $null
$draftSubmitStatusContract = $null
$draftSubmitStatusContractOk = $false
$draftSubmitStatusError = $null
$workerTemplateRunnerStatusContract = $null
$workerTemplateRunnerStatusContractOk = $false
$workerTemplateRunnerStatusError = $null
$liveSafeTaskPilotStatusContract = $null
$liveSafeTaskPilotStatusContractOk = $false
$liveSafeTaskPilotStatusError = $null
$matlabGoldenRunnerStatusContract = $null
$matlabGoldenRunnerStatusContractOk = $false
$matlabGoldenRunnerStatusError = $null
$liveMatlabGoldenTrialStatusContract = $null
$liveMatlabGoldenTrialStatusContractOk = $false
$liveMatlabGoldenTrialStatusError = $null
$matlabDoctorStatusContract = $null
$matlabDoctorStatusContractOk = $false
$matlabDoctorStatusError = $null
$liveMatlabRecoveryStatusContract = $null
$liveMatlabRecoveryStatusContractOk = $false
$liveMatlabRecoveryStatusError = $null
$liveMatlabSuccessStatusContract = $null
$liveMatlabSuccessStatusContractOk = $false
$liveMatlabSuccessStatusError = $null
$codexAnalysisReportRunnerStatusContract = $null
$codexAnalysisReportRunnerStatusContractOk = $false
$codexAnalysisReportRunnerStatusError = $null
$liveCodexAnalysisReportStatusContract = $null
$liveCodexAnalysisReportStatusContractOk = $false
$liveCodexAnalysisReportStatusError = $null
$liveCodexArtifactRecoveryStatusContract = $null
$liveCodexArtifactRecoveryStatusContractOk = $false
$liveCodexArtifactRecoveryStatusError = $null
$liveCodexNativeReportStatusContract = $null
$liveCodexNativeReportStatusContractOk = $false
$liveCodexNativeReportStatusError = $null
$workerInstallPreviewContract = $null
$workerInstallPreviewContractOk = $false
$workerInstallPreviewError = $null
$workerHeartbeatPreviewContract = $null
$workerHeartbeatPreviewContractOk = $false
$workerHeartbeatPreviewError = $null
$workerIdentityPreviewContract = $null
$workerIdentityPreviewContractOk = $false
$workerIdentityPreviewError = $null
$workerLiveHeartbeatPreviewContract = $null
$workerLiveHeartbeatPreviewContractOk = $false
$workerLiveHeartbeatPreviewError = $null
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-bootstrap-alpha-acceptance-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
  $statusScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-service-status.ps1"
  if (Test-Path -LiteralPath $statusScriptPath -PathType Leaf) {
    $rawStatus = & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusScriptPath -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $rawText = ($rawStatus | Out-String).Trim()
    Assert-NoUnsafeText $rawText
    $workerStatusContract = $rawText | ConvertFrom-Json
    $workerStatusContractOk = (
      [string]$workerStatusContract.schema -eq "skybridge.local_worker_service_status.v1" -and
      [bool]$workerStatusContract.claim_enabled -eq $false -and
      [bool]$workerStatusContract.execute_enabled -eq $false -and
      [bool]$workerStatusContract.worker_loop_started -eq $false -and
      [bool]$workerStatusContract.token_printed -eq $false
    )
  }
  $installScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-service-install.ps1"
  if (Test-Path -LiteralPath $installScriptPath -PathType Leaf) {
    $rawInstallPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $installScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $installPreviewText = ($rawInstallPreview | Out-String).Trim()
    Assert-NoUnsafeText $installPreviewText
    $workerInstallPreviewContract = $installPreviewText | ConvertFrom-Json
    $workerInstallPreviewContractOk = (
      [string]$workerInstallPreviewContract.schema -eq "skybridge.local_worker_service_install.v1" -and
      [string]$workerInstallPreviewContract.mode -eq "preview" -and
      [bool]$workerInstallPreviewContract.would_mutate -eq $false -and
      [bool]$workerInstallPreviewContract.did_mutate -eq $false -and
      [bool]$workerInstallPreviewContract.confirmation_required -eq $true -and
      [bool]$workerInstallPreviewContract.claim_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.execute_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.template_runner_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerInstallPreviewContract.codex_run_called -eq $false -and
      [bool]$workerInstallPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerInstallPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.token_printed -eq $false
    )
  }
  $heartbeatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-heartbeat-pairing-drill.ps1"
  if (Test-Path -LiteralPath $heartbeatScriptPath -PathType Leaf) {
    $rawHeartbeatPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $heartbeatScriptPath -Command heartbeat-preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $heartbeatPreviewText = ($rawHeartbeatPreview | Out-String).Trim()
    Assert-NoUnsafeText $heartbeatPreviewText
    $workerHeartbeatPreviewContract = $heartbeatPreviewText | ConvertFrom-Json
    $workerHeartbeatPreviewContractOk = (
      [string]$workerHeartbeatPreviewContract.schema -eq "skybridge.worker_heartbeat_pairing_drill.v1" -and
      [string]$workerHeartbeatPreviewContract.mode -eq "preview" -and
      [bool]$workerHeartbeatPreviewContract.would_mutate_server -eq $false -and
      [bool]$workerHeartbeatPreviewContract.server_mutation_performed -eq $false -and
      [bool]$workerHeartbeatPreviewContract.claim_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.execute_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.template_runner_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.claim_created -eq $false -and
      [bool]$workerHeartbeatPreviewContract.execution_started -eq $false -and
      [bool]$workerHeartbeatPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerHeartbeatPreviewContract.codex_run_called -eq $false -and
      [bool]$workerHeartbeatPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerHeartbeatPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.token_printed -eq $false
    )
  }
  $identityScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-identity.ps1"
  if (Test-Path -LiteralPath $identityScriptPath -PathType Leaf) {
    $rawIdentityPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $identityScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
    $identityPreviewText = ($rawIdentityPreview | Out-String).Trim()
    Assert-NoUnsafeText $identityPreviewText
    $workerIdentityPreviewContract = $identityPreviewText | ConvertFrom-Json
    $workerIdentityPreviewContractOk = (
      [string]$workerIdentityPreviewContract.schema -eq "skybridge.worker_identity.v1" -and
      [string]$workerIdentityPreviewContract.mode -eq "preview" -and
      [string]$workerIdentityPreviewContract.worker_id -eq "jerry-win-local-01" -and
      [bool]$workerIdentityPreviewContract.would_mutate -eq $false -and
      [bool]$workerIdentityPreviewContract.did_mutate -eq $false -and
      [bool]$workerIdentityPreviewContract.claim_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.execute_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerIdentityPreviewContract.codex_run_called -eq $false -and
      [bool]$workerIdentityPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerIdentityPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.token_printed -eq $false
    )
  }
  $liveHeartbeatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-live-heartbeat.ps1"
  if (Test-Path -LiteralPath $liveHeartbeatScriptPath -PathType Leaf) {
    $rawLiveHeartbeatPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveHeartbeatScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
    $liveHeartbeatPreviewText = ($rawLiveHeartbeatPreview | Out-String).Trim()
    Assert-NoUnsafeText $liveHeartbeatPreviewText
    $workerLiveHeartbeatPreviewContract = $liveHeartbeatPreviewText | ConvertFrom-Json
    $workerLiveHeartbeatPreviewContractOk = (
      [string]$workerLiveHeartbeatPreviewContract.schema -eq "skybridge.worker_live_heartbeat.v1" -and
      [string]$workerLiveHeartbeatPreviewContract.mode -eq "preview" -and
      [bool]$workerLiveHeartbeatPreviewContract.would_mutate_server -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.server_mutation_performed -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.claim_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.execute_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.claim_created -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.execution_started -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.codex_run_called -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.token_printed -eq $false
    )
  }
  $chatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-chat-to-task-draft.ps1"
  if (Test-Path -LiteralPath $chatScriptPath -PathType Leaf) {
    $rawChat = & pwsh -NoProfile -ExecutionPolicy Bypass -File $chatScriptPath -Command sample-matlab -ProjectId "skybridge-agent-hub" -Json
    $chatText = ($rawChat | Out-String).Trim()
    Assert-NoUnsafeText $chatText
    $chatToTaskContract = $chatText | ConvertFrom-Json
    $chatToTaskContractOk = (
      [string]$chatToTaskContract.schema -eq "skybridge.task_draft_preview.v1" -and
      [string]$chatToTaskContract.draft_type -eq "campaign" -and
      [string]$chatToTaskContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [bool]$chatToTaskContract.task_created -eq $false -and
      [bool]$chatToTaskContract.campaign_created -eq $false -and
      [bool]$chatToTaskContract.claim_created -eq $false -and
      [bool]$chatToTaskContract.execution_started -eq $false -and
      [bool]$chatToTaskContract.codex_run_called -eq $false -and
      [bool]$chatToTaskContract.matlab_run_called -eq $false -and
      [bool]$chatToTaskContract.arbitrary_shell_enabled -eq $false -and
      [bool]$chatToTaskContract.token_printed -eq $false
    )
  }
  $taskTemplateRegistryScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-task-template-registry.ps1"
  if (Test-Path -LiteralPath $taskTemplateRegistryScriptPath -PathType Leaf) {
    $rawRegistry = & pwsh -NoProfile -ExecutionPolicy Bypass -File $taskTemplateRegistryScriptPath -Command list -Json
    $registryText = ($rawRegistry | Out-String).Trim()
    Assert-NoUnsafeText $registryText
    $taskTemplateRegistryContract = $registryText | ConvertFrom-Json
    $requiredTemplateIds = @(
      "software-docs-task.v1",
      "codex-analysis-report.v1",
      "safe-local-smoke.v1",
      "matlab-parameter-sweep.v1",
      "matlab-result-analysis.v1"
    )
    $registryTemplateIds = @($taskTemplateRegistryContract.templates | ForEach-Object { [string]$_.template_id })
    $requiredTemplatesPresent = $true
    foreach ($id in $requiredTemplateIds) {
      if ($registryTemplateIds -notcontains $id) { $requiredTemplatesPresent = $false }
    }
    $forbiddenTemplateFlagsEnabled = @($taskTemplateRegistryContract.templates | Where-Object {
      $_.execution_supported -ne $false -or
      $_.task_creation_supported -ne $false -or
      $_.campaign_creation_supported -ne $false -or
      $_.claim_supported -ne $false -or
      $_.codex_run_supported -ne $false -or
      $_.matlab_run_supported -ne $false -or
      $_.arbitrary_shell_enabled -ne $false -or
      $_.token_printed -ne $false
    }).Count -gt 0
    $taskTemplateRegistryContractOk = (
      [string]$taskTemplateRegistryContract.schema -eq "skybridge.task_template_registry.v1" -and
      $requiredTemplatesPresent -and
      -not $forbiddenTemplateFlagsEnabled -and
      [bool]$taskTemplateRegistryContract.execution_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.task_creation_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.campaign_creation_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.claim_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.codex_run_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.matlab_run_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.arbitrary_shell_enabled -eq $false -and
      [bool]$taskTemplateRegistryContract.token_printed -eq $false
    )
  }
  $draftSubmitScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-draft-submit.ps1"
  if (Test-Path -LiteralPath $draftSubmitScriptPath -PathType Leaf) {
    $rawSubmit = & pwsh -NoProfile -ExecutionPolicy Bypass -File $draftSubmitScriptPath -Command status -Json
    $submitText = ($rawSubmit | Out-String).Trim()
    Assert-NoUnsafeText $submitText
    $draftSubmitStatusContract = $submitText | ConvertFrom-Json
    $draftSubmitStatusContractOk = (
      [string]$draftSubmitStatusContract.schema -eq "skybridge.draft_submit_status.v1" -and
      [bool]$draftSubmitStatusContract.confirmation_required -eq $true -and
      [bool]$draftSubmitStatusContract.preview_default -eq $true -and
      [bool]$draftSubmitStatusContract.task_created -eq $false -and
      [bool]$draftSubmitStatusContract.campaign_created -eq $false -and
      [bool]$draftSubmitStatusContract.claim_created -eq $false -and
      [bool]$draftSubmitStatusContract.execution_started -eq $false -and
      [bool]$draftSubmitStatusContract.codex_run_called -eq $false -and
      [bool]$draftSubmitStatusContract.matlab_run_called -eq $false -and
      [bool]$draftSubmitStatusContract.worker_loop_started -eq $false -and
      [bool]$draftSubmitStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$draftSubmitStatusContract.raw_prompt_persisted -eq $false -and
      [bool]$draftSubmitStatusContract.raw_response_persisted -eq $false -and
      [bool]$draftSubmitStatusContract.token_printed -eq $false
    )
  }
  $workerTemplateRunnerScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-template-runner.ps1"
  if (Test-Path -LiteralPath $workerTemplateRunnerScriptPath -PathType Leaf) {
    $rawRunner = & pwsh -NoProfile -ExecutionPolicy Bypass -File $workerTemplateRunnerScriptPath -Command status -Json
    $runnerText = ($rawRunner | Out-String).Trim()
    Assert-NoUnsafeText $runnerText
    $workerTemplateRunnerStatusContract = $runnerText | ConvertFrom-Json
    $workerTemplateRunnerStatusContractOk = (
      [string]$workerTemplateRunnerStatusContract.schema -eq "skybridge.worker_template_runner_status.v1" -and
      [bool]$workerTemplateRunnerStatusContract.confirmation_required -eq $true -and
      [bool]$workerTemplateRunnerStatusContract.preview_default -eq $true -and
      [int]$workerTemplateRunnerStatusContract.max_tasks -eq 1 -and
      @($workerTemplateRunnerStatusContract.supported_template_ids) -contains "safe-local-smoke.v1" -and
      @($workerTemplateRunnerStatusContract.supported_runner_ids) -contains "safe-local-smoke-runner.v1" -and
      [bool]$workerTemplateRunnerStatusContract.codex_run_called -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.matlab_run_called -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.worker_loop_started -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.unbounded_run_enabled -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.project_control_unpaused -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.token_printed -eq $false
    )
  }
  $liveSafeTaskPilotScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-safe-task-pilot.ps1"
  if (Test-Path -LiteralPath $liveSafeTaskPilotScriptPath -PathType Leaf) {
    $rawPilot = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveSafeTaskPilotScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-safe-template-task-332-001" -Json
    $pilotText = ($rawPilot | Out-String).Trim()
    Assert-NoUnsafeText $pilotText
    $liveSafeTaskPilotStatusContract = $pilotText | ConvertFrom-Json
    $liveSafeTaskPilotStatusContractOk = (
      [string]$liveSafeTaskPilotStatusContract.schema -eq "skybridge.live_safe_task_pilot_safe_summary.v1" -and
      [string]$liveSafeTaskPilotStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveSafeTaskPilotStatusContract.task_id -eq "live-safe-template-task-332-001" -and
      [string]$liveSafeTaskPilotStatusContract.template_id -eq "safe-local-smoke.v1" -and
      [string]$liveSafeTaskPilotStatusContract.runner_id -eq "safe-local-smoke-runner.v1" -and
      [bool]$liveSafeTaskPilotStatusContract.claim_created -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.execution_started -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.worker_loop_started -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.codex_run_called -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.matlab_run_called -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveSafeTaskPilotStatusContract.token_printed -eq $false
    )
  }
  $matlabRunnerScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-matlab-parameter-sweep-runner.ps1"
  if (Test-Path -LiteralPath $matlabRunnerScriptPath -PathType Leaf) {
    $rawMatlabRunner = & pwsh -NoProfile -ExecutionPolicy Bypass -File $matlabRunnerScriptPath -Command status -TaskId "live-matlab-golden-task-333-001" -WorkerId "jerry-win-local-01" -Json
    $matlabRunnerText = ($rawMatlabRunner | Out-String).Trim()
    Assert-NoUnsafeText $matlabRunnerText
    $matlabGoldenRunnerStatusContract = $matlabRunnerText | ConvertFrom-Json
    $matlabGoldenRunnerStatusContractOk = (
      [string]$matlabGoldenRunnerStatusContract.schema -eq "skybridge.matlab_parameter_sweep_runner.v1" -and
      [string]$matlabGoldenRunnerStatusContract.task_id -eq "live-matlab-golden-task-333-001" -and
      [string]$matlabGoldenRunnerStatusContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [string]$matlabGoldenRunnerStatusContract.runner_id -eq "matlab-parameter-sweep-runner.v1" -and
      [int]$matlabGoldenRunnerStatusContract.combination_count -eq 2 -and
      [bool]$matlabGoldenRunnerStatusContract.matlab_invoked -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.raw_stdout_included -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.raw_stderr_included -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.raw_mat_files_uploaded -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.codex_run_called -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.worker_loop_started -eq $false -and
      [bool]$matlabGoldenRunnerStatusContract.token_printed -eq $false
    )
  }
  $liveMatlabGoldenTrialScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-matlab-golden-trial.ps1"
  if (Test-Path -LiteralPath $liveMatlabGoldenTrialScriptPath -PathType Leaf) {
    $rawMatlabTrial = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveMatlabGoldenTrialScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-matlab-golden-task-333-001" -Json
    $matlabTrialText = ($rawMatlabTrial | Out-String).Trim()
    Assert-NoUnsafeText $matlabTrialText
    $liveMatlabGoldenTrialStatusContract = $matlabTrialText | ConvertFrom-Json
    $liveMatlabGoldenTrialStatusContractOk = (
      [string]$liveMatlabGoldenTrialStatusContract.schema -eq "skybridge.live_matlab_golden_trial_safe_summary.v1" -and
      [string]$liveMatlabGoldenTrialStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveMatlabGoldenTrialStatusContract.task_id -eq "live-matlab-golden-task-333-001" -and
      [string]$liveMatlabGoldenTrialStatusContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [string]$liveMatlabGoldenTrialStatusContract.runner_id -eq "matlab-parameter-sweep-runner.v1" -and
      [bool]$liveMatlabGoldenTrialStatusContract.claim_created -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.execution_started -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.worker_loop_started -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.codex_run_called -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveMatlabGoldenTrialStatusContract.token_printed -eq $false
    )
  }
  $matlabDoctorScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-matlab-doctor.ps1"
  if (Test-Path -LiteralPath $matlabDoctorScriptPath -PathType Leaf) {
    $rawMatlabDoctor = & pwsh -NoProfile -ExecutionPolicy Bypass -File $matlabDoctorScriptPath -Command safe-summary -Json
    $matlabDoctorText = ($rawMatlabDoctor | Out-String).Trim()
    Assert-NoUnsafeText $matlabDoctorText
    $matlabDoctorStatusContract = $matlabDoctorText | ConvertFrom-Json
    $matlabDoctorStatusContractOk = (
      [string]$matlabDoctorStatusContract.schema -eq "skybridge.matlab_doctor.v1" -and
      [string]$matlabDoctorStatusContract.mode -eq "safe-summary" -and
      [bool]$matlabDoctorStatusContract.matlab_invoked -eq $false -and
      [bool]$matlabDoctorStatusContract.claim_created -eq $false -and
      [bool]$matlabDoctorStatusContract.execution_started -eq $false -and
      [bool]$matlabDoctorStatusContract.codex_run_called -eq $false -and
      [bool]$matlabDoctorStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$matlabDoctorStatusContract.worker_loop_started -eq $false -and
      [bool]$matlabDoctorStatusContract.project_control_unpaused -eq $false -and
      [bool]$matlabDoctorStatusContract.raw_stdout_included -eq $false -and
      [bool]$matlabDoctorStatusContract.raw_stderr_included -eq $false -and
      [bool]$matlabDoctorStatusContract.token_printed -eq $false
    )
  }
  $liveMatlabRecoveryScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-matlab-golden-recovery.ps1"
  if (Test-Path -LiteralPath $liveMatlabRecoveryScriptPath -PathType Leaf) {
    $rawMatlabRecovery = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveMatlabRecoveryScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-matlab-golden-task-334-001" -Json
    $matlabRecoveryText = ($rawMatlabRecovery | Out-String).Trim()
    Assert-NoUnsafeText $matlabRecoveryText
    $liveMatlabRecoveryStatusContract = $matlabRecoveryText | ConvertFrom-Json
    $liveMatlabRecoveryStatusContractOk = (
      [string]$liveMatlabRecoveryStatusContract.schema -eq "skybridge.live_matlab_golden_recovery_safe_summary.v1" -and
      [string]$liveMatlabRecoveryStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveMatlabRecoveryStatusContract.task_id -eq "live-matlab-golden-task-334-001" -and
      [string]$liveMatlabRecoveryStatusContract.previous_failed_task_id -eq "live-matlab-golden-task-333-001" -and
      [string]$liveMatlabRecoveryStatusContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [string]$liveMatlabRecoveryStatusContract.runner_id -eq "matlab-parameter-sweep-runner.v1" -and
      [bool]$liveMatlabRecoveryStatusContract.claim_created -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.execution_started -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.worker_loop_started -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.codex_run_called -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveMatlabRecoveryStatusContract.token_printed -eq $false
    )
  }
  $liveMatlabSuccessScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-matlab-golden-success.ps1"
  if (Test-Path -LiteralPath $liveMatlabSuccessScriptPath -PathType Leaf) {
    $rawMatlabSuccess = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveMatlabSuccessScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-matlab-golden-task-336-001" -Json
    $matlabSuccessText = ($rawMatlabSuccess | Out-String).Trim()
    Assert-NoUnsafeText $matlabSuccessText
    $liveMatlabSuccessStatusContract = $matlabSuccessText | ConvertFrom-Json
    $liveMatlabSuccessStatusContractOk = (
      [string]$liveMatlabSuccessStatusContract.schema -eq "skybridge.live_matlab_golden_success_safe_summary.v1" -and
      [string]$liveMatlabSuccessStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveMatlabSuccessStatusContract.task_id -eq "live-matlab-golden-task-336-001" -and
      @($liveMatlabSuccessStatusContract.do_not_reuse_task_ids) -contains "live-matlab-golden-task-333-001" -and
      @($liveMatlabSuccessStatusContract.do_not_reuse_task_ids) -contains "live-matlab-golden-task-334-001" -and
      [string]$liveMatlabSuccessStatusContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [string]$liveMatlabSuccessStatusContract.runner_id -eq "matlab-parameter-sweep-runner.v1" -and
      [bool]$liveMatlabSuccessStatusContract.claim_created -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.execution_started -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.worker_loop_started -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.codex_run_called -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveMatlabSuccessStatusContract.token_printed -eq $false
    )
  }
  $codexAnalysisReportRunnerScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-codex-analysis-report-runner.ps1"
  if (Test-Path -LiteralPath $codexAnalysisReportRunnerScriptPath -PathType Leaf) {
    $rawCodexRunner = & pwsh -NoProfile -ExecutionPolicy Bypass -File $codexAnalysisReportRunnerScriptPath -Command status -TaskId "live-codex-analysis-report-task-337-001" -WorkerId "jerry-win-local-01" -Json
    $codexRunnerText = ($rawCodexRunner | Out-String).Trim()
    Assert-NoUnsafeText $codexRunnerText
    $codexAnalysisReportRunnerStatusContract = $codexRunnerText | ConvertFrom-Json
    $codexAnalysisReportRunnerStatusContractOk = (
      [string]$codexAnalysisReportRunnerStatusContract.schema -eq "skybridge.codex_analysis_report_runner.v1" -and
      [string]$codexAnalysisReportRunnerStatusContract.task_id -eq "live-codex-analysis-report-task-337-001" -and
      [string]$codexAnalysisReportRunnerStatusContract.template_id -eq "codex-analysis-report.v1" -and
      [string]$codexAnalysisReportRunnerStatusContract.runner_id -eq "codex-analysis-report-runner.v1" -and
      [bool]$codexAnalysisReportRunnerStatusContract.would_invoke_codex -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.codex_invoked -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.raw_codex_log_included -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.raw_prompt_included -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.raw_stdout_included -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.raw_stderr_included -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.matlab_run_called -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.worker_loop_started -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.pr_created -eq $false -and
      [bool]$codexAnalysisReportRunnerStatusContract.token_printed -eq $false
    )
  }
  $liveCodexAnalysisReportScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-codex-analysis-report-trial.ps1"
  if (Test-Path -LiteralPath $liveCodexAnalysisReportScriptPath -PathType Leaf) {
    $rawCodexTrial = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveCodexAnalysisReportScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-codex-analysis-report-task-337-001" -Json
    $codexTrialText = ($rawCodexTrial | Out-String).Trim()
    Assert-NoUnsafeText $codexTrialText
    $liveCodexAnalysisReportStatusContract = $codexTrialText | ConvertFrom-Json
    $liveCodexAnalysisReportStatusContractOk = (
      [string]$liveCodexAnalysisReportStatusContract.schema -eq "skybridge.live_codex_analysis_report_safe_summary.v1" -and
      [string]$liveCodexAnalysisReportStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveCodexAnalysisReportStatusContract.task_id -eq "live-codex-analysis-report-task-337-001" -and
      [string]$liveCodexAnalysisReportStatusContract.template_id -eq "codex-analysis-report.v1" -and
      [string]$liveCodexAnalysisReportStatusContract.runner_id -eq "codex-analysis-report-runner.v1" -and
      [bool]$liveCodexAnalysisReportStatusContract.claim_created -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.execution_started -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.matlab_run_called -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.worker_loop_started -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.pr_created -eq $false -and
      [bool]$liveCodexAnalysisReportStatusContract.token_printed -eq $false
    )
  }
  $liveCodexArtifactRecoveryScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-codex-analysis-report-recovery.ps1"
  if (Test-Path -LiteralPath $liveCodexArtifactRecoveryScriptPath -PathType Leaf) {
    $rawCodexRecovery = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveCodexArtifactRecoveryScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-codex-analysis-report-task-338-001" -Json
    $codexRecoveryText = ($rawCodexRecovery | Out-String).Trim()
    Assert-NoUnsafeText $codexRecoveryText
    $liveCodexArtifactRecoveryStatusContract = $codexRecoveryText | ConvertFrom-Json
    $liveCodexArtifactRecoveryStatusContractOk = (
      [string]$liveCodexArtifactRecoveryStatusContract.schema -eq "skybridge.live_codex_analysis_report_recovery_safe_summary.v1" -and
      [string]$liveCodexArtifactRecoveryStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveCodexArtifactRecoveryStatusContract.task_id -eq "live-codex-analysis-report-task-338-001" -and
      @($liveCodexArtifactRecoveryStatusContract.do_not_reuse_task_ids) -contains "live-codex-analysis-report-task-337-001" -and
      [string]$liveCodexArtifactRecoveryStatusContract.template_id -eq "codex-analysis-report.v1" -and
      [string]$liveCodexArtifactRecoveryStatusContract.runner_id -eq "codex-analysis-report-runner.v1" -and
      [bool]$liveCodexArtifactRecoveryStatusContract.claim_created -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.execution_started -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.matlab_run_called -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.worker_loop_started -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.pr_created -eq $false -and
      [bool]$liveCodexArtifactRecoveryStatusContract.token_printed -eq $false
    )
  }
  $liveCodexNativeReportScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-live-codex-analysis-report-native-success.ps1"
  if (Test-Path -LiteralPath $liveCodexNativeReportScriptPath -PathType Leaf) {
    $rawCodexNative = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveCodexNativeReportScriptPath -Command safe-summary -WorkerId "jerry-win-local-01" -TaskId "live-codex-analysis-report-task-339-001" -Json
    $codexNativeText = ($rawCodexNative | Out-String).Trim()
    Assert-NoUnsafeText $codexNativeText
    $liveCodexNativeReportStatusContract = $codexNativeText | ConvertFrom-Json
    $liveCodexNativeReportStatusContractOk = (
      [string]$liveCodexNativeReportStatusContract.schema -eq "skybridge.live_codex_native_report_safe_summary.v1" -and
      [string]$liveCodexNativeReportStatusContract.worker_id -eq "jerry-win-local-01" -and
      [string]$liveCodexNativeReportStatusContract.task_id -eq "live-codex-analysis-report-task-339-001" -and
      @($liveCodexNativeReportStatusContract.do_not_reuse_task_ids) -contains "live-codex-analysis-report-task-337-001" -and
      @($liveCodexNativeReportStatusContract.do_not_reuse_task_ids) -contains "live-codex-analysis-report-task-338-001" -and
      [string]$liveCodexNativeReportStatusContract.template_id -eq "codex-analysis-report.v1" -and
      [string]$liveCodexNativeReportStatusContract.runner_id -eq "codex-analysis-report-runner.v1" -and
      [string]$liveCodexNativeReportStatusContract.final_report_source -eq "none" -and
      [bool]$liveCodexNativeReportStatusContract.fallback_report_used -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.native_report_valid -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.claim_created -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.execution_started -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.matlab_run_called -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.worker_loop_started -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.project_control_unpaused -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.pr_created -eq $false -and
      [bool]$liveCodexNativeReportStatusContract.token_printed -eq $false
    )
  }
} catch {
  if (-not $workerStatusContractOk) {
    $workerStatusError = "worker_service_status_contract_failed"
  }
  if (-not $chatToTaskContractOk) {
    $chatToTaskError = "chat_to_task_contract_failed"
  }
  if (-not $taskTemplateRegistryContractOk) {
    $taskTemplateRegistryError = "task_template_registry_contract_failed"
  }
  if (-not $draftSubmitStatusContractOk) {
    $draftSubmitStatusError = "draft_submit_status_contract_failed"
  }
  if (-not $workerTemplateRunnerStatusContractOk) {
    $workerTemplateRunnerStatusError = "worker_template_runner_status_contract_failed"
  }
  if (-not $liveSafeTaskPilotStatusContractOk) {
    $liveSafeTaskPilotStatusError = "live_safe_task_pilot_status_contract_failed"
  }
  if (-not $matlabGoldenRunnerStatusContractOk) {
    $matlabGoldenRunnerStatusError = "matlab_golden_runner_status_contract_failed"
  }
  if (-not $liveMatlabGoldenTrialStatusContractOk) {
    $liveMatlabGoldenTrialStatusError = "live_matlab_golden_trial_status_contract_failed"
  }
  if (-not $matlabDoctorStatusContractOk) {
    $matlabDoctorStatusError = "matlab_doctor_status_contract_failed"
  }
  if (-not $liveMatlabRecoveryStatusContractOk) {
    $liveMatlabRecoveryStatusError = "live_matlab_recovery_status_contract_failed"
  }
  if (-not $liveMatlabSuccessStatusContractOk) {
    $liveMatlabSuccessStatusError = "live_matlab_success_status_contract_failed"
  }
  if (-not $codexAnalysisReportRunnerStatusContractOk) {
    $codexAnalysisReportRunnerStatusError = "codex_analysis_report_runner_status_contract_failed"
  }
  if (-not $liveCodexAnalysisReportStatusContractOk) {
    $liveCodexAnalysisReportStatusError = "live_codex_analysis_report_status_contract_failed"
  }
  if (-not $liveCodexArtifactRecoveryStatusContractOk) {
    $liveCodexArtifactRecoveryStatusError = "live_codex_artifact_recovery_status_contract_failed"
  }
  if (-not $liveCodexNativeReportStatusContractOk) {
    $liveCodexNativeReportStatusError = "live_codex_native_report_status_contract_failed"
  }
  if (-not $workerInstallPreviewContractOk) {
    $workerInstallPreviewError = "worker_install_preview_contract_failed"
  }
  if (-not $workerHeartbeatPreviewContractOk) {
    $workerHeartbeatPreviewError = "worker_heartbeat_preview_contract_failed"
  }
  if (-not $workerIdentityPreviewContractOk) {
    $workerIdentityPreviewError = "worker_identity_preview_contract_failed"
  }
  if (-not $workerLiveHeartbeatPreviewContractOk) {
    $workerLiveHeartbeatPreviewError = "worker_live_heartbeat_preview_contract_failed"
  }
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}

$ok = (
  $missingDocs.Count -eq 0 -and
  $missingScripts.Count -eq 0 -and
  $missingComponents.Count -eq 0 -and
  $missingPackageScripts.Count -eq 0 -and
  $workerSupportPresent -and
  $docSecretFindings.Count -eq 0 -and
  $desktopWorkerServiceManagerPresent -and
  $desktopChatToTaskPanelPresent -and
  $desktopTaskTemplateRegistryPanelPresent -and
  $desktopDraftReviewSubmitPanelPresent -and
  $desktopWorkerTemplateRunnerPanelPresent -and
  $desktopLiveSafeTaskPilotPresent -and
  $desktopMatlabGoldenTrialPresent -and
  $desktopMatlabRecoveryPresent -and
  $desktopMatlabRuntimeRepairPresent -and
  $desktopMatlabGoldenSuccessPresent -and
  $desktopCodexAnalysisReportPresent -and
  $desktopCodexArtifactRecoveryPresent -and
  $desktopCodexNativeReportPresent -and
  $desktopWorkerInstallFlowPresent -and
  $desktopWorkerIdentityHeartbeatPresent -and
  $workerStatusContractOk -and
  $workerInstallPreviewContractOk -and
  $workerHeartbeatPreviewContractOk -and
  $workerIdentityPreviewContractOk -and
  $workerLiveHeartbeatPreviewContractOk -and
  $chatToTaskContractOk -and
  $taskTemplateRegistryContractOk -and
  $draftSubmitStatusContractOk -and
  $workerTemplateRunnerStatusContractOk -and
  $liveSafeTaskPilotStatusContractOk -and
  $matlabGoldenRunnerStatusContractOk -and
  $liveMatlabGoldenTrialStatusContractOk -and
  $matlabDoctorStatusContractOk -and
  $liveMatlabRecoveryStatusContractOk -and
  $liveMatlabSuccessStatusContractOk -and
  $codexAnalysisReportRunnerStatusContractOk -and
  $liveCodexAnalysisReportStatusContractOk -and
  $liveCodexArtifactRecoveryStatusContractOk -and
  $liveCodexNativeReportStatusContractOk
)

$report = [pscustomobject]@{
  schema = "skybridge.bootstrap_alpha_acceptance.v1"
  ok = $ok
  expected_docs = $docResults
  package_scripts = $packageScriptResults
  required_scripts = $scriptResults
  components = $componentResults
  worker_support_present = $workerSupportPresent
  worker_support_candidates = $workerResults
  bootstrap_alpha_rc_gate_present = (Test-RelativePath -RelativePath "scripts/powershell/skybridge-bootstrap-alpha-rc-gate.ps1" -Leaf)
  bootstrap_alpha_rc_release_notes_present = (Test-RelativePath -RelativePath "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md" -Leaf)
  bootstrap_alpha_rc_runbook_present = (Test-RelativePath -RelativePath "docs/release/BOOTSTRAP_ALPHA_RC_RUNBOOK.md" -Leaf)
  bootstrap_alpha_disabled_features_present = (Test-RelativePath -RelativePath "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md" -Leaf)
  bootstrap_alpha_tag_plan_present = (Test-RelativePath -RelativePath "docs/release/BOOTSTRAP_ALPHA_TAG_PLAN.md" -Leaf)
  bootstrap_alpha_rc_report_smoke_present = (Test-RelativePath -RelativePath "scripts/powershell/smoke-bootstrap-alpha-rc-report.ps1" -Leaf)
  bootstrap_alpha_tag_preview_smoke_present = (Test-RelativePath -RelativePath "scripts/powershell/smoke-bootstrap-alpha-tag-preview.ps1" -Leaf)
  bootstrap_alpha_rc1_handoff_present = (Test-RelativePath -RelativePath "docs/release/BOOTSTRAP_ALPHA_RC1_HANDOFF.md" -Leaf)
  bootstrap_alpha_rc1_handoff_checker_present = (Test-RelativePath -RelativePath "scripts/powershell/skybridge-bootstrap-alpha-rc1-handoff.ps1" -Leaf)
  codex_stop_hook_hygiene_present = (Test-RelativePath -RelativePath "docs/dev/CODEX_STOP_HOOK_HYGIENE.md" -Leaf)
  bootstrap_alpha_rc1_handoff_smoke_present = (Test-RelativePath -RelativePath "scripts/powershell/smoke-bootstrap-alpha-rc1-handoff.ps1" -Leaf)
  codex_stop_hook_hygiene_smoke_present = (Test-RelativePath -RelativePath "scripts/powershell/smoke-codex-stop-hook-hygiene.ps1" -Leaf)
  desktop_worker_service_manager_present = $desktopWorkerServiceManagerPresent
  desktop_chat_to_task_panel_present = $desktopChatToTaskPanelPresent
  desktop_task_template_registry_panel_present = $desktopTaskTemplateRegistryPanelPresent
  desktop_draft_review_submit_panel_present = $desktopDraftReviewSubmitPanelPresent
  desktop_worker_template_runner_panel_present = $desktopWorkerTemplateRunnerPanelPresent
  desktop_live_safe_task_pilot_present = $desktopLiveSafeTaskPilotPresent
  desktop_matlab_golden_trial_present = $desktopMatlabGoldenTrialPresent
  desktop_matlab_recovery_present = $desktopMatlabRecoveryPresent
  desktop_matlab_runtime_repair_present = $desktopMatlabRuntimeRepairPresent
  desktop_matlab_golden_success_present = $desktopMatlabGoldenSuccessPresent
  desktop_codex_analysis_report_present = $desktopCodexAnalysisReportPresent
  desktop_codex_artifact_recovery_present = $desktopCodexArtifactRecoveryPresent
  desktop_codex_native_report_present = $desktopCodexNativeReportPresent
  desktop_worker_install_flow_present = $desktopWorkerInstallFlowPresent
  desktop_worker_identity_heartbeat_present = $desktopWorkerIdentityHeartbeatPresent
  worker_service_status_contract_ok = $workerStatusContractOk
  worker_service_status_contract = if ($workerStatusContract) {
    [pscustomobject]@{
      schema = $workerStatusContract.schema
      readiness_status = $workerStatusContract.readiness_status
      claim_enabled = $workerStatusContract.claim_enabled
      execute_enabled = $workerStatusContract.execute_enabled
      worker_loop_started = $workerStatusContract.worker_loop_started
      token_printed = $workerStatusContract.token_printed
    }
  } else { $null }
  worker_service_status_error = $workerStatusError
  worker_install_preview_contract_ok = $workerInstallPreviewContractOk
  worker_install_preview_contract = if ($workerInstallPreviewContract) {
    [pscustomobject]@{
      schema = $workerInstallPreviewContract.schema
      mode = $workerInstallPreviewContract.mode
      would_mutate = $workerInstallPreviewContract.would_mutate
      did_mutate = $workerInstallPreviewContract.did_mutate
      confirmation_required = $workerInstallPreviewContract.confirmation_required
      claim_enabled = $workerInstallPreviewContract.claim_enabled
      execute_enabled = $workerInstallPreviewContract.execute_enabled
      template_runner_enabled = $workerInstallPreviewContract.template_runner_enabled
      worker_loop_started = $workerInstallPreviewContract.worker_loop_started
      codex_run_called = $workerInstallPreviewContract.codex_run_called
      matlab_run_called = $workerInstallPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerInstallPreviewContract.arbitrary_shell_enabled
      token_printed = $workerInstallPreviewContract.token_printed
    }
  } else { $null }
  worker_install_preview_error = $workerInstallPreviewError
  worker_heartbeat_preview_contract_ok = $workerHeartbeatPreviewContractOk
  worker_heartbeat_preview_contract = if ($workerHeartbeatPreviewContract) {
    [pscustomobject]@{
      schema = $workerHeartbeatPreviewContract.schema
      mode = $workerHeartbeatPreviewContract.mode
      would_mutate_server = $workerHeartbeatPreviewContract.would_mutate_server
      server_mutation_performed = $workerHeartbeatPreviewContract.server_mutation_performed
      claim_enabled = $workerHeartbeatPreviewContract.claim_enabled
      execute_enabled = $workerHeartbeatPreviewContract.execute_enabled
      template_runner_enabled = $workerHeartbeatPreviewContract.template_runner_enabled
      claim_created = $workerHeartbeatPreviewContract.claim_created
      execution_started = $workerHeartbeatPreviewContract.execution_started
      worker_loop_started = $workerHeartbeatPreviewContract.worker_loop_started
      codex_run_called = $workerHeartbeatPreviewContract.codex_run_called
      matlab_run_called = $workerHeartbeatPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerHeartbeatPreviewContract.arbitrary_shell_enabled
      token_printed = $workerHeartbeatPreviewContract.token_printed
    }
  } else { $null }
  worker_heartbeat_preview_error = $workerHeartbeatPreviewError
  worker_identity_preview_contract_ok = $workerIdentityPreviewContractOk
  worker_identity_preview_contract = if ($workerIdentityPreviewContract) {
    [pscustomobject]@{
      schema = $workerIdentityPreviewContract.schema
      mode = $workerIdentityPreviewContract.mode
      worker_id = $workerIdentityPreviewContract.worker_id
      would_mutate = $workerIdentityPreviewContract.would_mutate
      did_mutate = $workerIdentityPreviewContract.did_mutate
      claim_enabled = $workerIdentityPreviewContract.claim_enabled
      execute_enabled = $workerIdentityPreviewContract.execute_enabled
      worker_loop_started = $workerIdentityPreviewContract.worker_loop_started
      codex_run_called = $workerIdentityPreviewContract.codex_run_called
      matlab_run_called = $workerIdentityPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerIdentityPreviewContract.arbitrary_shell_enabled
      token_printed = $workerIdentityPreviewContract.token_printed
    }
  } else { $null }
  worker_identity_preview_error = $workerIdentityPreviewError
  worker_live_heartbeat_preview_contract_ok = $workerLiveHeartbeatPreviewContractOk
  worker_live_heartbeat_preview_contract = if ($workerLiveHeartbeatPreviewContract) {
    [pscustomobject]@{
      schema = $workerLiveHeartbeatPreviewContract.schema
      mode = $workerLiveHeartbeatPreviewContract.mode
      worker_id = $workerLiveHeartbeatPreviewContract.worker_id
      would_mutate_server = $workerLiveHeartbeatPreviewContract.would_mutate_server
      server_mutation_performed = $workerLiveHeartbeatPreviewContract.server_mutation_performed
      claim_enabled = $workerLiveHeartbeatPreviewContract.claim_enabled
      execute_enabled = $workerLiveHeartbeatPreviewContract.execute_enabled
      claim_created = $workerLiveHeartbeatPreviewContract.claim_created
      execution_started = $workerLiveHeartbeatPreviewContract.execution_started
      worker_loop_started = $workerLiveHeartbeatPreviewContract.worker_loop_started
      codex_run_called = $workerLiveHeartbeatPreviewContract.codex_run_called
      matlab_run_called = $workerLiveHeartbeatPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerLiveHeartbeatPreviewContract.arbitrary_shell_enabled
      token_printed = $workerLiveHeartbeatPreviewContract.token_printed
    }
  } else { $null }
  worker_live_heartbeat_preview_error = $workerLiveHeartbeatPreviewError
  chat_to_task_contract_ok = $chatToTaskContractOk
  chat_to_task_contract = if ($chatToTaskContract) {
    [pscustomobject]@{
      schema = $chatToTaskContract.schema
      status = $chatToTaskContract.status
      draft_type = $chatToTaskContract.draft_type
      template_id = $chatToTaskContract.template_id
      task_created = $chatToTaskContract.task_created
      campaign_created = $chatToTaskContract.campaign_created
      claim_created = $chatToTaskContract.claim_created
      execution_started = $chatToTaskContract.execution_started
      codex_run_called = $chatToTaskContract.codex_run_called
      matlab_run_called = $chatToTaskContract.matlab_run_called
      arbitrary_shell_enabled = $chatToTaskContract.arbitrary_shell_enabled
      token_printed = $chatToTaskContract.token_printed
    }
  } else { $null }
  chat_to_task_error = $chatToTaskError
  task_template_registry_contract_ok = $taskTemplateRegistryContractOk
  task_template_registry_contract = if ($taskTemplateRegistryContract) {
    [pscustomobject]@{
      schema = $taskTemplateRegistryContract.schema
      template_count = @($taskTemplateRegistryContract.templates).Count
      template_ids = @($taskTemplateRegistryContract.templates | ForEach-Object { [string]$_.template_id })
      execution_supported = $taskTemplateRegistryContract.execution_supported
      task_creation_supported = $taskTemplateRegistryContract.task_creation_supported
      campaign_creation_supported = $taskTemplateRegistryContract.campaign_creation_supported
      claim_supported = $taskTemplateRegistryContract.claim_supported
      codex_run_supported = $taskTemplateRegistryContract.codex_run_supported
      matlab_run_supported = $taskTemplateRegistryContract.matlab_run_supported
      arbitrary_shell_enabled = $taskTemplateRegistryContract.arbitrary_shell_enabled
      token_printed = $taskTemplateRegistryContract.token_printed
    }
  } else { $null }
  task_template_registry_error = $taskTemplateRegistryError
  draft_submit_status_contract_ok = $draftSubmitStatusContractOk
  draft_submit_status_contract = if ($draftSubmitStatusContract) {
    [pscustomobject]@{
      schema = $draftSubmitStatusContract.schema
      confirmation_required = $draftSubmitStatusContract.confirmation_required
      preview_default = $draftSubmitStatusContract.preview_default
      task_created = $draftSubmitStatusContract.task_created
      campaign_created = $draftSubmitStatusContract.campaign_created
      claim_created = $draftSubmitStatusContract.claim_created
      execution_started = $draftSubmitStatusContract.execution_started
      codex_run_called = $draftSubmitStatusContract.codex_run_called
      matlab_run_called = $draftSubmitStatusContract.matlab_run_called
      worker_loop_started = $draftSubmitStatusContract.worker_loop_started
      arbitrary_shell_enabled = $draftSubmitStatusContract.arbitrary_shell_enabled
      raw_prompt_persisted = $draftSubmitStatusContract.raw_prompt_persisted
      raw_response_persisted = $draftSubmitStatusContract.raw_response_persisted
      token_printed = $draftSubmitStatusContract.token_printed
    }
  } else { $null }
  draft_submit_status_error = $draftSubmitStatusError
  worker_template_runner_status_contract_ok = $workerTemplateRunnerStatusContractOk
  worker_template_runner_status_contract = if ($workerTemplateRunnerStatusContract) {
    [pscustomobject]@{
      schema = $workerTemplateRunnerStatusContract.schema
      confirmation_required = $workerTemplateRunnerStatusContract.confirmation_required
      preview_default = $workerTemplateRunnerStatusContract.preview_default
      max_tasks = $workerTemplateRunnerStatusContract.max_tasks
      supported_template_ids = $workerTemplateRunnerStatusContract.supported_template_ids
      supported_runner_ids = $workerTemplateRunnerStatusContract.supported_runner_ids
      codex_run_called = $workerTemplateRunnerStatusContract.codex_run_called
      matlab_run_called = $workerTemplateRunnerStatusContract.matlab_run_called
      arbitrary_shell_enabled = $workerTemplateRunnerStatusContract.arbitrary_shell_enabled
      worker_loop_started = $workerTemplateRunnerStatusContract.worker_loop_started
      unbounded_run_enabled = $workerTemplateRunnerStatusContract.unbounded_run_enabled
      project_control_unpaused = $workerTemplateRunnerStatusContract.project_control_unpaused
      token_printed = $workerTemplateRunnerStatusContract.token_printed
    }
  } else { $null }
  worker_template_runner_status_error = $workerTemplateRunnerStatusError
  live_safe_task_pilot_status_contract_ok = $liveSafeTaskPilotStatusContractOk
  live_safe_task_pilot_status_contract = if ($liveSafeTaskPilotStatusContract) {
    [pscustomobject]@{
      schema = $liveSafeTaskPilotStatusContract.schema
      worker_id = $liveSafeTaskPilotStatusContract.worker_id
      task_id = $liveSafeTaskPilotStatusContract.task_id
      template_id = $liveSafeTaskPilotStatusContract.template_id
      runner_id = $liveSafeTaskPilotStatusContract.runner_id
      claim_created = $liveSafeTaskPilotStatusContract.claim_created
      execution_started = $liveSafeTaskPilotStatusContract.execution_started
      worker_loop_started = $liveSafeTaskPilotStatusContract.worker_loop_started
      codex_run_called = $liveSafeTaskPilotStatusContract.codex_run_called
      matlab_run_called = $liveSafeTaskPilotStatusContract.matlab_run_called
      arbitrary_shell_enabled = $liveSafeTaskPilotStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveSafeTaskPilotStatusContract.project_control_unpaused
      token_printed = $liveSafeTaskPilotStatusContract.token_printed
    }
  } else { $null }
  live_safe_task_pilot_status_error = $liveSafeTaskPilotStatusError
  matlab_golden_runner_status_contract_ok = $matlabGoldenRunnerStatusContractOk
  matlab_golden_runner_status_contract = if ($matlabGoldenRunnerStatusContract) {
    [pscustomobject]@{
      schema = $matlabGoldenRunnerStatusContract.schema
      mode = $matlabGoldenRunnerStatusContract.mode
      task_id = $matlabGoldenRunnerStatusContract.task_id
      template_id = $matlabGoldenRunnerStatusContract.template_id
      runner_id = $matlabGoldenRunnerStatusContract.runner_id
      combination_count = $matlabGoldenRunnerStatusContract.combination_count
      matlab_available = $matlabGoldenRunnerStatusContract.matlab_available
      matlab_invoked = $matlabGoldenRunnerStatusContract.matlab_invoked
      raw_stdout_included = $matlabGoldenRunnerStatusContract.raw_stdout_included
      raw_stderr_included = $matlabGoldenRunnerStatusContract.raw_stderr_included
      raw_mat_files_uploaded = $matlabGoldenRunnerStatusContract.raw_mat_files_uploaded
      codex_run_called = $matlabGoldenRunnerStatusContract.codex_run_called
      arbitrary_shell_enabled = $matlabGoldenRunnerStatusContract.arbitrary_shell_enabled
      worker_loop_started = $matlabGoldenRunnerStatusContract.worker_loop_started
      token_printed = $matlabGoldenRunnerStatusContract.token_printed
    }
  } else { $null }
  matlab_golden_runner_status_error = $matlabGoldenRunnerStatusError
  live_matlab_golden_trial_status_contract_ok = $liveMatlabGoldenTrialStatusContractOk
  live_matlab_golden_trial_status_contract = if ($liveMatlabGoldenTrialStatusContract) {
    [pscustomobject]@{
      schema = $liveMatlabGoldenTrialStatusContract.schema
      worker_id = $liveMatlabGoldenTrialStatusContract.worker_id
      task_id = $liveMatlabGoldenTrialStatusContract.task_id
      template_id = $liveMatlabGoldenTrialStatusContract.template_id
      runner_id = $liveMatlabGoldenTrialStatusContract.runner_id
      claim_created = $liveMatlabGoldenTrialStatusContract.claim_created
      execution_started = $liveMatlabGoldenTrialStatusContract.execution_started
      worker_loop_started = $liveMatlabGoldenTrialStatusContract.worker_loop_started
      codex_run_called = $liveMatlabGoldenTrialStatusContract.codex_run_called
      arbitrary_shell_enabled = $liveMatlabGoldenTrialStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveMatlabGoldenTrialStatusContract.project_control_unpaused
      token_printed = $liveMatlabGoldenTrialStatusContract.token_printed
    }
  } else { $null }
  live_matlab_golden_trial_status_error = $liveMatlabGoldenTrialStatusError
  matlab_doctor_status_contract_ok = $matlabDoctorStatusContractOk
  matlab_doctor_status_contract = if ($matlabDoctorStatusContract) {
    [pscustomobject]@{
      schema = $matlabDoctorStatusContract.schema
      mode = $matlabDoctorStatusContract.mode
      matlab_detected = $matlabDoctorStatusContract.matlab_detected
      matlab_invoked = $matlabDoctorStatusContract.matlab_invoked
      fixed_script_visible = $matlabDoctorStatusContract.fixed_script_visible
      raw_stdout_included = $matlabDoctorStatusContract.raw_stdout_included
      raw_stderr_included = $matlabDoctorStatusContract.raw_stderr_included
      codex_run_called = $matlabDoctorStatusContract.codex_run_called
      arbitrary_shell_enabled = $matlabDoctorStatusContract.arbitrary_shell_enabled
      worker_loop_started = $matlabDoctorStatusContract.worker_loop_started
      project_control_unpaused = $matlabDoctorStatusContract.project_control_unpaused
      token_printed = $matlabDoctorStatusContract.token_printed
    }
  } else { $null }
  matlab_doctor_status_error = $matlabDoctorStatusError
  live_matlab_recovery_status_contract_ok = $liveMatlabRecoveryStatusContractOk
  live_matlab_recovery_status_contract = if ($liveMatlabRecoveryStatusContract) {
    [pscustomobject]@{
      schema = $liveMatlabRecoveryStatusContract.schema
      worker_id = $liveMatlabRecoveryStatusContract.worker_id
      task_id = $liveMatlabRecoveryStatusContract.task_id
      previous_failed_task_id = $liveMatlabRecoveryStatusContract.previous_failed_task_id
      template_id = $liveMatlabRecoveryStatusContract.template_id
      runner_id = $liveMatlabRecoveryStatusContract.runner_id
      claim_created = $liveMatlabRecoveryStatusContract.claim_created
      execution_started = $liveMatlabRecoveryStatusContract.execution_started
      worker_loop_started = $liveMatlabRecoveryStatusContract.worker_loop_started
      codex_run_called = $liveMatlabRecoveryStatusContract.codex_run_called
      arbitrary_shell_enabled = $liveMatlabRecoveryStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveMatlabRecoveryStatusContract.project_control_unpaused
      token_printed = $liveMatlabRecoveryStatusContract.token_printed
    }
  } else { $null }
  live_matlab_recovery_status_error = $liveMatlabRecoveryStatusError
  live_matlab_success_status_contract_ok = $liveMatlabSuccessStatusContractOk
  live_matlab_success_status_contract = if ($liveMatlabSuccessStatusContract) {
    [pscustomobject]@{
      schema = $liveMatlabSuccessStatusContract.schema
      worker_id = $liveMatlabSuccessStatusContract.worker_id
      task_id = $liveMatlabSuccessStatusContract.task_id
      do_not_reuse_task_ids = $liveMatlabSuccessStatusContract.do_not_reuse_task_ids
      template_id = $liveMatlabSuccessStatusContract.template_id
      runner_id = $liveMatlabSuccessStatusContract.runner_id
      claim_created = $liveMatlabSuccessStatusContract.claim_created
      execution_started = $liveMatlabSuccessStatusContract.execution_started
      worker_loop_started = $liveMatlabSuccessStatusContract.worker_loop_started
      codex_run_called = $liveMatlabSuccessStatusContract.codex_run_called
      arbitrary_shell_enabled = $liveMatlabSuccessStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveMatlabSuccessStatusContract.project_control_unpaused
      token_printed = $liveMatlabSuccessStatusContract.token_printed
    }
  } else { $null }
  live_matlab_success_status_error = $liveMatlabSuccessStatusError
  codex_analysis_report_runner_status_contract_ok = $codexAnalysisReportRunnerStatusContractOk
  codex_analysis_report_runner_status_contract = if ($codexAnalysisReportRunnerStatusContract) {
    [pscustomobject]@{
      schema = $codexAnalysisReportRunnerStatusContract.schema
      mode = $codexAnalysisReportRunnerStatusContract.mode
      task_id = $codexAnalysisReportRunnerStatusContract.task_id
      template_id = $codexAnalysisReportRunnerStatusContract.template_id
      runner_id = $codexAnalysisReportRunnerStatusContract.runner_id
      input_manifest_path = $codexAnalysisReportRunnerStatusContract.input_manifest_path
      input_summary_path = $codexAnalysisReportRunnerStatusContract.input_summary_path
      input_metrics_path = $codexAnalysisReportRunnerStatusContract.input_metrics_path
      output_report_path = $codexAnalysisReportRunnerStatusContract.output_report_path
      report_exists = $codexAnalysisReportRunnerStatusContract.report_exists
      codex_available = $codexAnalysisReportRunnerStatusContract.codex_available
      would_invoke_codex = $codexAnalysisReportRunnerStatusContract.would_invoke_codex
      codex_invoked = $codexAnalysisReportRunnerStatusContract.codex_invoked
      raw_codex_log_included = $codexAnalysisReportRunnerStatusContract.raw_codex_log_included
      raw_prompt_included = $codexAnalysisReportRunnerStatusContract.raw_prompt_included
      raw_stdout_included = $codexAnalysisReportRunnerStatusContract.raw_stdout_included
      raw_stderr_included = $codexAnalysisReportRunnerStatusContract.raw_stderr_included
      matlab_run_called = $codexAnalysisReportRunnerStatusContract.matlab_run_called
      arbitrary_shell_enabled = $codexAnalysisReportRunnerStatusContract.arbitrary_shell_enabled
      worker_loop_started = $codexAnalysisReportRunnerStatusContract.worker_loop_started
      pr_created = $codexAnalysisReportRunnerStatusContract.pr_created
      token_printed = $codexAnalysisReportRunnerStatusContract.token_printed
    }
  } else { $null }
  codex_analysis_report_runner_status_error = $codexAnalysisReportRunnerStatusError
  live_codex_analysis_report_status_contract_ok = $liveCodexAnalysisReportStatusContractOk
  live_codex_analysis_report_status_contract = if ($liveCodexAnalysisReportStatusContract) {
    [pscustomobject]@{
      schema = $liveCodexAnalysisReportStatusContract.schema
      worker_id = $liveCodexAnalysisReportStatusContract.worker_id
      task_id = $liveCodexAnalysisReportStatusContract.task_id
      template_id = $liveCodexAnalysisReportStatusContract.template_id
      runner_id = $liveCodexAnalysisReportStatusContract.runner_id
      claim_created = $liveCodexAnalysisReportStatusContract.claim_created
      execution_started = $liveCodexAnalysisReportStatusContract.execution_started
      matlab_run_called = $liveCodexAnalysisReportStatusContract.matlab_run_called
      worker_loop_started = $liveCodexAnalysisReportStatusContract.worker_loop_started
      arbitrary_shell_enabled = $liveCodexAnalysisReportStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveCodexAnalysisReportStatusContract.project_control_unpaused
      pr_created = $liveCodexAnalysisReportStatusContract.pr_created
      token_printed = $liveCodexAnalysisReportStatusContract.token_printed
    }
  } else { $null }
  live_codex_analysis_report_status_error = $liveCodexAnalysisReportStatusError
  live_codex_artifact_recovery_status_contract_ok = $liveCodexArtifactRecoveryStatusContractOk
  live_codex_artifact_recovery_status_contract = if ($liveCodexArtifactRecoveryStatusContract) {
    [pscustomobject]@{
      schema = $liveCodexArtifactRecoveryStatusContract.schema
      worker_id = $liveCodexArtifactRecoveryStatusContract.worker_id
      task_id = $liveCodexArtifactRecoveryStatusContract.task_id
      expected_task_id = $liveCodexArtifactRecoveryStatusContract.expected_task_id
      do_not_reuse_task_ids = $liveCodexArtifactRecoveryStatusContract.do_not_reuse_task_ids
      template_id = $liveCodexArtifactRecoveryStatusContract.template_id
      runner_id = $liveCodexArtifactRecoveryStatusContract.runner_id
      output_report_path = $liveCodexArtifactRecoveryStatusContract.output_report_path
      claim_created = $liveCodexArtifactRecoveryStatusContract.claim_created
      execution_started = $liveCodexArtifactRecoveryStatusContract.execution_started
      matlab_run_called = $liveCodexArtifactRecoveryStatusContract.matlab_run_called
      worker_loop_started = $liveCodexArtifactRecoveryStatusContract.worker_loop_started
      arbitrary_shell_enabled = $liveCodexArtifactRecoveryStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveCodexArtifactRecoveryStatusContract.project_control_unpaused
      pr_created = $liveCodexArtifactRecoveryStatusContract.pr_created
      token_printed = $liveCodexArtifactRecoveryStatusContract.token_printed
    }
  } else { $null }
  live_codex_artifact_recovery_status_error = $liveCodexArtifactRecoveryStatusError
  live_codex_native_report_status_contract_ok = $liveCodexNativeReportStatusContractOk
  live_codex_native_report_status_contract = if ($liveCodexNativeReportStatusContract) {
    [pscustomobject]@{
      schema = $liveCodexNativeReportStatusContract.schema
      worker_id = $liveCodexNativeReportStatusContract.worker_id
      task_id = $liveCodexNativeReportStatusContract.task_id
      expected_task_id = $liveCodexNativeReportStatusContract.expected_task_id
      do_not_reuse_task_ids = $liveCodexNativeReportStatusContract.do_not_reuse_task_ids
      template_id = $liveCodexNativeReportStatusContract.template_id
      runner_id = $liveCodexNativeReportStatusContract.runner_id
      output_report_path = $liveCodexNativeReportStatusContract.output_report_path
      final_report_source = $liveCodexNativeReportStatusContract.final_report_source
      fallback_report_used = $liveCodexNativeReportStatusContract.fallback_report_used
      native_report_valid = $liveCodexNativeReportStatusContract.native_report_valid
      claim_created = $liveCodexNativeReportStatusContract.claim_created
      execution_started = $liveCodexNativeReportStatusContract.execution_started
      matlab_run_called = $liveCodexNativeReportStatusContract.matlab_run_called
      worker_loop_started = $liveCodexNativeReportStatusContract.worker_loop_started
      arbitrary_shell_enabled = $liveCodexNativeReportStatusContract.arbitrary_shell_enabled
      project_control_unpaused = $liveCodexNativeReportStatusContract.project_control_unpaused
      pr_created = $liveCodexNativeReportStatusContract.pr_created
      token_printed = $liveCodexNativeReportStatusContract.token_printed
    }
  } else { $null }
  live_codex_native_report_status_error = $liveCodexNativeReportStatusError
  doc_secret_marker_findings = $docSecretFindings
  missing_docs = $missingDocs
  missing_scripts = $missingScripts
  missing_components = $missingComponents
  missing_package_scripts = $missingPackageScripts
  raw_secret_markers_in_new_docs = ($docSecretFindings.Count -gt 0)
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} elseif ($ok) {
  Complete-Smoke "bootstrap-alpha-acceptance"
} else {
  $report | Format-List
}

if (-not $ok) {
  exit 1
}
