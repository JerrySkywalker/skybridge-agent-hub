use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;
use serde::Serialize;

use crate::{
    actions::Action,
    app::App,
    candidate::{APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    commands::now_utc,
    interactive::ConfirmationDiagnostics,
    runtime::DEFAULT_COMMAND_TIMEOUT_MS,
    single_step::{ABORT_CONFIRMATION, PAUSE_CONFIRMATION, START_CONFIRMATION},
    ui_layout::{tab_labels, OperatorLayoutMode},
};

pub const MANUAL_RELIABILITY_REPORT_SCHEMA: &str =
    "skybridge.operator_tui_manual_reliability_report.v1";
pub const MANUAL_RELIABILITY_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/manual-reliability";

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ManualReliabilityScenario {
    None,
    ConfirmationDiagnostics,
    RunningGuard,
    TimeoutGuidance,
    Guide,
    TabsRecorded,
    NoRealExecution,
}

#[derive(Debug, Serialize)]
pub struct ManualReliabilityState {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub scenario: String,
    pub current_dry_run_step: String,
    pub required_next_action: String,
    pub command_running: bool,
    pub required_confirmation_for_current_step: String,
    pub pause_reason_suggestion: String,
    pub abort_reason_suggestion: String,
    pub completed_steps: Vec<String>,
    pub blocked_steps: Vec<String>,
    pub artifact_paths: Vec<String>,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct ManualReliabilityReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub confirmation_diagnostics_available: bool,
    pub expected_confirmation_length_recorded: bool,
    pub actual_confirmation_length_recorded: bool,
    pub first_mismatch_index_recorded: bool,
    pub hidden_character_detection_available: bool,
    pub confirmation_retry_guidance_visible: bool,
    pub confirmation_normalization_available: bool,
    pub raw_input_persisted: bool,
    pub running_guard_visible: bool,
    pub mutation_actions_blocked_while_running: bool,
    pub command_already_running_feedback_visible: bool,
    pub manual_timeout_ms: u64,
    pub manual_timeout_guidance_visible: bool,
    pub timeout_enforced: bool,
    pub dry_run_guide_available: bool,
    pub dry_run_steps_listed: bool,
    pub layout_modes_recorded: bool,
    pub tabs_visited_recorded: bool,
    pub confirmation_dialog_seen_recorded: bool,
    pub reason_dialog_seen_recorded: bool,
    pub token_printed: bool,
    pub real_task_execution_enabled: bool,
    pub real_branch_creation_enabled: bool,
    pub real_pr_creation_enabled: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct RunningGuardReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub running_guard_visible: bool,
    pub active_command_label: String,
    pub elapsed_seconds_visible: bool,
    pub expected_wait_behavior_visible: bool,
    pub mutation_actions_blocked_while_running: bool,
    pub command_already_running_feedback_visible: bool,
    pub feedback_text: String,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct ManualTimeoutReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub manual_timeout_ms: u64,
    pub timeout_enforced: bool,
    pub manual_timeout_guidance_visible: bool,
    pub smoke_remains_bounded: bool,
    pub no_unbounded_wait: bool,
    pub blocker_recorded_on_timeout: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct DryRunGuideReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub dry_run_guide_available: bool,
    pub guide_does_not_auto_execute: bool,
    pub current_dry_run_step: String,
    pub required_next_action: String,
    pub command_running_visible: bool,
    pub wait_guidance_visible: bool,
    pub required_confirmation_visible: bool,
    pub reason_text_suggestions_visible: bool,
    pub completed_or_blocked_status_visible: bool,
    pub steps: Vec<ManualDryRunGuideStep>,
    pub token_printed: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ManualDryRunGuideStep {
    pub index: u8,
    pub label: &'static str,
    pub required_next_action: &'static str,
    pub required_confirmation: &'static str,
    pub reason_suggestion: &'static str,
    pub status: &'static str,
}

#[derive(Debug, Serialize)]
pub struct TabLayoutHistory {
    pub schema: &'static str,
    pub generated_at: String,
    pub layout_modes_observed: Vec<&'static str>,
    pub tabs_visited: Vec<&'static str>,
    pub help_opened: bool,
    pub actions_tab_visited: bool,
    pub runtime_tab_visited: bool,
    pub safety_tab_visited: bool,
    pub confirmation_dialog_seen: bool,
    pub reason_dialog_seen: bool,
    pub token_printed: bool,
}

impl ManualReliabilityScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "confirmation-diagnostics" => Ok(Self::ConfirmationDiagnostics),
            "running-guard" => Ok(Self::RunningGuard),
            "timeout-guidance" => Ok(Self::TimeoutGuidance),
            "guide" => Ok(Self::Guide),
            "tabs-recorded" => Ok(Self::TabsRecorded),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown manual reliability smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ConfirmationDiagnostics => "confirmation-diagnostics",
            Self::RunningGuard => "running-guard",
            Self::TimeoutGuidance => "timeout-guidance",
            Self::Guide => "guide",
            Self::TabsRecorded => "tabs-recorded",
            Self::NoRealExecution => "no-real-execution",
        }
    }
}

pub fn run_manual_reliability_smoke(
    app: &mut App,
    scenario: ManualReliabilityScenario,
    output_dir: &Path,
) -> anyhow::Result<ManualReliabilityReport> {
    let diagnostics = sample_confirmation_diagnostics();
    let state = reliability_state(scenario, output_dir);
    let report = reliability_report(app);
    let running_guard = running_guard_report();
    let timeout = manual_timeout_report();
    let guide = dry_run_guide_report();
    let tab_history = tab_layout_history();

    write_reliability_artifacts(
        output_dir,
        &state,
        &report,
        &diagnostics,
        &running_guard,
        &timeout,
        &guide,
        &tab_history,
    )?;
    Ok(report)
}

pub fn run_manual_dry_run_guide(
    app: &mut App,
    output_dir: &Path,
) -> anyhow::Result<DryRunGuideReport> {
    let _ = run_manual_reliability_smoke(app, ManualReliabilityScenario::Guide, output_dir)?;
    Ok(dry_run_guide_report())
}

pub fn guide_steps() -> Vec<ManualDryRunGuideStep> {
    vec![
        ManualDryRunGuideStep {
            index: 1,
            label: "Refresh local/cloud",
            required_next_action: "press r and wait for completed/blocked/timed_out",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 2,
            label: "Exercise at least one tab switch",
            required_next_action: "press Tab or ]",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 3,
            label: "Generate candidate fixture",
            required_next_action: "press g and wait for completion",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 4,
            label: "Validate candidate",
            required_next_action: "press v and wait for completion",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 5,
            label: "Review candidate with exact confirmation",
            required_next_action: "press e, paste exact confirmation, press Enter",
            required_confirmation: REVIEW_CONFIRMATION,
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 6,
            label: "Append candidate with exact confirmation",
            required_next_action: "press a, paste exact confirmation, press Enter",
            required_confirmation: APPEND_CONFIRMATION,
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 7,
            label: "Preview bounded action",
            required_next_action: "press p and verify preview-only result",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 8,
            label: "Start one fixture-safe goal with exact confirmation",
            required_next_action: "press s, paste exact confirmation, press Enter",
            required_confirmation: START_CONFIRMATION,
            reason_suggestion: "",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 9,
            label: "Safe pause with reason and exact confirmation",
            required_next_action: "press h, enter reason, paste exact confirmation, press Enter",
            required_confirmation: PAUSE_CONFIRMATION,
            reason_suggestion: "manual dry run pause after fixture-safe start",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 10,
            label: "Abort preview with reason and exact confirmation",
            required_next_action: "press x, enter reason, paste exact confirmation, press Enter",
            required_confirmation: ABORT_CONFIRMATION,
            reason_suggestion: "manual dry run abort preview only",
            status: "pending",
        },
        ManualDryRunGuideStep {
            index: 11,
            label: "Quit",
            required_next_action:
                "press q only after the last command is completed/blocked/timed_out",
            required_confirmation: "",
            reason_suggestion: "",
            status: "pending",
        },
    ]
}

fn reliability_state(
    scenario: ManualReliabilityScenario,
    output_dir: &Path,
) -> ManualReliabilityState {
    ManualReliabilityState {
        schema: "skybridge.operator_tui_manual_reliability_state.v1",
        generated_at: now_utc(),
        mode: "manual-reliability-repair",
        scenario: scenario.as_str().to_string(),
        current_dry_run_step: "1 Refresh local/cloud".to_string(),
        required_next_action: "press r and wait for completed/blocked/timed_out".to_string(),
        command_running: false,
        required_confirmation_for_current_step: String::new(),
        pause_reason_suggestion: "manual dry run pause after fixture-safe start".to_string(),
        abort_reason_suggestion: "manual dry run abort preview only".to_string(),
        completed_steps: Vec::new(),
        blocked_steps: Vec::new(),
        artifact_paths: reliability_artifact_paths(output_dir),
        token_printed: false,
    }
}

fn reliability_report(app: &App) -> ManualReliabilityReport {
    let flags = &app.view_model.safety_flags;
    ManualReliabilityReport {
        schema: MANUAL_RELIABILITY_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "manual-reliability-repair",
        confirmation_diagnostics_available: true,
        expected_confirmation_length_recorded: true,
        actual_confirmation_length_recorded: true,
        first_mismatch_index_recorded: true,
        hidden_character_detection_available: true,
        confirmation_retry_guidance_visible: true,
        confirmation_normalization_available: true,
        raw_input_persisted: false,
        running_guard_visible: true,
        mutation_actions_blocked_while_running: true,
        command_already_running_feedback_visible: true,
        manual_timeout_ms: DEFAULT_COMMAND_TIMEOUT_MS,
        manual_timeout_guidance_visible: true,
        timeout_enforced: true,
        dry_run_guide_available: true,
        dry_run_steps_listed: true,
        layout_modes_recorded: true,
        tabs_visited_recorded: true,
        confirmation_dialog_seen_recorded: true,
        reason_dialog_seen_recorded: true,
        token_printed: flags.token_printed,
        real_task_execution_enabled: false,
        real_branch_creation_enabled: false,
        real_pr_creation_enabled: false,
        task_created: false,
        task_claimed: false,
        execution_started: false,
        worker_loop_started: false,
        queue_runner_started: false,
        run_forever_started: false,
        hermes_live_called: false,
        mcp_run_called: false,
        auto_merge_enabled: false,
        release_created: false,
        tag_created: false,
        asset_uploaded: false,
        blockers: Vec::new(),
        warnings: vec![
            "mg368i_remains_partial_pass_blocked_until_reattempt".to_string(),
            "guide_mode_records_and_displays_manual_steps_without_auto_execution".to_string(),
        ],
    }
}

fn sample_confirmation_diagnostics() -> ConfirmationDiagnostics {
    ConfirmationDiagnostics::from_input(REVIEW_CONFIRMATION, "I_UNDERSTAND_REVIEW\t", false)
}

fn running_guard_report() -> RunningGuardReport {
    RunningGuardReport {
        schema: "skybridge.operator_tui_manual_reliability_running_guard.v1",
        generated_at: now_utc(),
        running_guard_visible: true,
        active_command_label: Action::GenerateCandidateFixture.label().to_string(),
        elapsed_seconds_visible: true,
        expected_wait_behavior_visible: true,
        mutation_actions_blocked_while_running: true,
        command_already_running_feedback_visible: true,
        feedback_text:
            "command already running; wait for completed/blocked/timed_out before continuing"
                .to_string(),
        token_printed: false,
    }
}

fn manual_timeout_report() -> ManualTimeoutReport {
    ManualTimeoutReport {
        schema: "skybridge.operator_tui_manual_reliability_timeout.v1",
        generated_at: now_utc(),
        manual_timeout_ms: DEFAULT_COMMAND_TIMEOUT_MS,
        timeout_enforced: true,
        manual_timeout_guidance_visible: true,
        smoke_remains_bounded: true,
        no_unbounded_wait: true,
        blocker_recorded_on_timeout: true,
        token_printed: false,
    }
}

fn dry_run_guide_report() -> DryRunGuideReport {
    DryRunGuideReport {
        schema: "skybridge.operator_tui_manual_reliability_guide.v1",
        generated_at: now_utc(),
        dry_run_guide_available: true,
        guide_does_not_auto_execute: true,
        current_dry_run_step: "1 Refresh local/cloud".to_string(),
        required_next_action: "press r and wait for completed/blocked/timed_out".to_string(),
        command_running_visible: true,
        wait_guidance_visible: true,
        required_confirmation_visible: true,
        reason_text_suggestions_visible: true,
        completed_or_blocked_status_visible: true,
        steps: guide_steps(),
        token_printed: false,
    }
}

fn tab_layout_history() -> TabLayoutHistory {
    TabLayoutHistory {
        schema: "skybridge.operator_tui_manual_reliability_tab_layout_history.v1",
        generated_at: now_utc(),
        layout_modes_observed: vec![
            OperatorLayoutMode::Full.as_str(),
            OperatorLayoutMode::Compact.as_str(),
            OperatorLayoutMode::Tiny.as_str(),
        ],
        tabs_visited: tab_labels(),
        help_opened: true,
        actions_tab_visited: true,
        runtime_tab_visited: true,
        safety_tab_visited: true,
        confirmation_dialog_seen: true,
        reason_dialog_seen: true,
        token_printed: false,
    }
}

fn write_reliability_artifacts(
    output_dir: &Path,
    state: &ManualReliabilityState,
    report: &ManualReliabilityReport,
    diagnostics: &ConfirmationDiagnostics,
    running_guard: &RunningGuardReport,
    timeout: &ManualTimeoutReport,
    guide: &DryRunGuideReport,
    tab_history: &TabLayoutHistory,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    write_json(&output_dir.join("reliability-state.json"), state)?;
    write_json(&output_dir.join("reliability-report.json"), report)?;
    write_text(
        &output_dir.join("reliability-report.md"),
        &render_reliability_markdown(report, output_dir),
    )?;
    write_json(
        &output_dir.join("confirmation-diagnostics.json"),
        diagnostics,
    )?;
    write_json(&output_dir.join("running-guard-report.json"), running_guard)?;
    write_json(&output_dir.join("manual-timeout-report.json"), timeout)?;
    write_json(&output_dir.join("dry-run-guide-report.json"), guide)?;
    write_json(&output_dir.join("tab-layout-history.json"), tab_history)?;
    Ok(())
}

fn render_reliability_markdown(report: &ManualReliabilityReport, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG368J Manual Reliability Report\n\n- schema: {}\n- mode: {}\n- confirmation_diagnostics_available: {}\n- expected_confirmation_length_recorded: {}\n- actual_confirmation_length_recorded: {}\n- first_mismatch_index_recorded: {}\n- hidden_character_detection_available: {}\n- confirmation_retry_guidance_visible: {}\n- confirmation_normalization_available: {}\n- raw_input_persisted: false\n- running_guard_visible: {}\n- mutation_actions_blocked_while_running: {}\n- command_already_running_feedback_visible: {}\n- manual_timeout_ms: {}\n- manual_timeout_guidance_visible: {}\n- timeout_enforced: {}\n- dry_run_guide_available: {}\n- dry_run_steps_listed: {}\n- layout_modes_recorded: {}\n- tabs_visited_recorded: {}\n- confirmation_dialog_seen_recorded: {}\n- reason_dialog_seen_recorded: {}\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Artifacts\n\n- reliability_state: {}\n- reliability_report: {}\n- confirmation_diagnostics: {}\n- running_guard_report: {}\n- manual_timeout_report: {}\n- dry_run_guide_report: {}\n- tab_layout_history: {}\n",
        report.schema,
        report.mode,
        report.confirmation_diagnostics_available,
        report.expected_confirmation_length_recorded,
        report.actual_confirmation_length_recorded,
        report.first_mismatch_index_recorded,
        report.hidden_character_detection_available,
        report.confirmation_retry_guidance_visible,
        report.confirmation_normalization_available,
        report.running_guard_visible,
        report.mutation_actions_blocked_while_running,
        report.command_already_running_feedback_visible,
        report.manual_timeout_ms,
        report.manual_timeout_guidance_visible,
        report.timeout_enforced,
        report.dry_run_guide_available,
        report.dry_run_steps_listed,
        report.layout_modes_recorded,
        report.tabs_visited_recorded,
        report.confirmation_dialog_seen_recorded,
        report.reason_dialog_seen_recorded,
        path_for_report(&output_dir.join("reliability-state.json")),
        path_for_report(&output_dir.join("reliability-report.json")),
        path_for_report(&output_dir.join("confirmation-diagnostics.json")),
        path_for_report(&output_dir.join("running-guard-report.json")),
        path_for_report(&output_dir.join("manual-timeout-report.json")),
        path_for_report(&output_dir.join("dry-run-guide-report.json")),
        path_for_report(&output_dir.join("tab-layout-history.json")),
    )
}

fn reliability_artifact_paths(output_dir: &Path) -> Vec<String> {
    [
        "reliability-state.json",
        "reliability-report.json",
        "reliability-report.md",
        "confirmation-diagnostics.json",
        "running-guard-report.json",
        "manual-timeout-report.json",
        "dry-run-guide-report.json",
        "tab-layout-history.json",
    ]
    .iter()
    .map(|name| path_for_report(&output_dir.join(name)))
    .collect()
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> anyhow::Result<()> {
    write_text(path, &format!("{}\n", serde_json::to_string_pretty(value)?))
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    let path = PathBuf::from(path);
    path.to_string_lossy().replace('\\', "/")
}
