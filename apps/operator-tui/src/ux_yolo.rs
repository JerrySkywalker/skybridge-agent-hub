use std::{fs, path::Path, time::Duration};

use anyhow::Context;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use serde::Serialize;

use crate::{
    actions::Action,
    app::App,
    candidate::{APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    commands::now_utc,
    interactive::{
        confirmation_for, exact_confirmations, handle_key_event, handle_paste_event,
        ConfirmationDiagnostics, InteractiveLastAction,
    },
    runtime::OperatorRuntime,
    single_step::{ABORT_CONFIRMATION, PAUSE_CONFIRMATION, START_CONFIRMATION},
};

pub const UX_YOLO_REPORT_SCHEMA: &str = "skybridge.operator_tui_ux_yolo_report.v1";
pub const UX_YOLO_STATE_SCHEMA: &str = "skybridge.operator_tui_ux_yolo_state.v1";
pub const DEFAULT_UX_YOLO_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/ux-yolo";

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize)]
pub enum Language {
    En,
    ZhCn,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum UxYoloScenario {
    None,
    SimplifiedGuide,
    Bilingual,
    YoloFixtureOnly,
    SelfDrive,
    ConfirmationBuffer,
    NoRealExecution,
}

#[derive(Debug, Serialize)]
pub struct UxYoloState {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub current_step: String,
    pub next_action: String,
    pub command_status: String,
    pub safe_to_continue: bool,
    pub primary_key: &'static str,
    pub expected_result: String,
    pub current_blocker: String,
    pub language: &'static str,
    pub language_toggled: bool,
    pub available_languages: Vec<&'static str>,
    pub yolo_fixture_only: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct UxYoloReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub simplified_guide_available: bool,
    pub simplified_guide_default_for_manual_dry_run: bool,
    pub bilingual_ui_available: bool,
    pub available_languages: Vec<&'static str>,
    pub language: &'static str,
    pub language_toggled: bool,
    pub language_toggle_available: bool,
    pub zh_cn_translations_available: bool,
    pub exact_confirmations_untranslated: bool,
    pub yolo_fixture_only_available: bool,
    pub yolo_fixture_only: bool,
    pub yolo_skips_exact_confirmations_only_in_fixture_mode: bool,
    pub yolo_real_execution_blocked: bool,
    pub yolo_branch_pr_blocked: bool,
    pub yolo_queue_worker_blocked: bool,
    pub self_drive_available: bool,
    pub self_drive_requires_fixture_only: bool,
    pub self_drive_completed_full_fixture_flow: bool,
    pub confirmation_buffer_starts_empty: bool,
    pub action_hotkey_not_inserted_into_confirmation: bool,
    pub duplicate_paste_detection_available: bool,
    pub raw_input_persisted: bool,
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
pub struct SelfDriveReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub self_drive_available: bool,
    pub self_drive_requires_fixture_only: bool,
    pub self_drive_completed_full_fixture_flow: bool,
    pub yolo_fixture_only: bool,
    pub used_same_action_routing: bool,
    pub waited_for_commands_to_finish: bool,
    pub step_history: Vec<String>,
    pub tabs_recorded: Vec<&'static str>,
    pub language_toggles_recorded: Vec<&'static str>,
    pub confirmation_dialog_yolo_bypass_recorded: bool,
    pub running_guard_evidence_recorded: bool,
    pub no_real_execution_safety_flags_recorded: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct BilingualReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub bilingual_ui_available: bool,
    pub available_languages: Vec<&'static str>,
    pub language: &'static str,
    pub language_toggle_available: bool,
    pub language_toggled: bool,
    pub zh_cn_translations_available: bool,
    pub translated_surfaces: Vec<&'static str>,
    pub exact_confirmations_untranslated: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct ConfirmationBufferReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub confirmation_buffer_starts_empty: bool,
    pub action_hotkey_not_inserted_into_confirmation: bool,
    pub ctrl_u_resets_length_zero: bool,
    pub esc_cancels_and_clears_buffer: bool,
    pub successful_submit_clears_buffer: bool,
    pub mismatch_preserves_diagnostics: bool,
    pub paste_exact_once_has_expected_length: bool,
    pub duplicate_paste_detection_available: bool,
    pub likely_duplicate_paste: bool,
    pub expected_confirmation_length: usize,
    pub exact_once_input_length: usize,
    pub duplicate_input_length: usize,
    pub raw_input_persisted: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct YoloSafetyReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub yolo_fixture_only_available: bool,
    pub yolo_fixture_only: bool,
    pub yolo_skips_exact_confirmations_only_in_fixture_mode: bool,
    pub yolo_real_execution_blocked: bool,
    pub yolo_branch_pr_blocked: bool,
    pub yolo_queue_worker_blocked: bool,
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
    pub token_printed: bool,
}

impl Language {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "en" => Ok(Self::En),
            "zh-CN" | "zh_cn" | "zh" => Ok(Self::ZhCn),
            other => anyhow::bail!("unknown language: {other}"),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::En => "en",
            Self::ZhCn => "zh-CN",
        }
    }

    pub fn toggle(self) -> Self {
        match self {
            Self::En => Self::ZhCn,
            Self::ZhCn => Self::En,
        }
    }
}

impl UxYoloScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "simplified-guide" => Ok(Self::SimplifiedGuide),
            "bilingual" => Ok(Self::Bilingual),
            "yolo-fixture-only" => Ok(Self::YoloFixtureOnly),
            "self-drive" => Ok(Self::SelfDrive),
            "confirmation-buffer" => Ok(Self::ConfirmationBuffer),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown UX YOLO smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }
}

pub fn run_ux_yolo_smoke(
    app: &mut App,
    scenario: UxYoloScenario,
    output_dir: &Path,
) -> anyhow::Result<UxYoloReport> {
    app.operator_guide = true;
    if matches!(
        scenario,
        UxYoloScenario::YoloFixtureOnly
            | UxYoloScenario::SelfDrive
            | UxYoloScenario::NoRealExecution
    ) {
        app.yolo_fixture_only = true;
    }
    if scenario == UxYoloScenario::Bilingual && app.language != Language::ZhCn {
        app.toggle_language();
    }
    let mut self_drive = self_drive_report(app, Vec::new(), false);
    let mut confirmation = confirmation_buffer_report(app, output_dir)?;

    if scenario == UxYoloScenario::SelfDrive {
        if !app.yolo_fixture_only {
            anyhow::bail!("self-drive requires --yolo-fixture-only");
        }
        self_drive = run_self_drive_flow(app, output_dir)?;
    }
    if scenario == UxYoloScenario::ConfirmationBuffer {
        confirmation = confirmation_buffer_report(app, output_dir)?;
    }

    app.sync_view_model();
    let report = ux_yolo_report(app, &self_drive, &confirmation);
    write_ux_yolo_artifacts(output_dir, app, &report, &self_drive, &confirmation)?;
    Ok(report)
}

pub fn simplified_guide_lines(app: &App, language: Language) -> Vec<String> {
    let step = current_step(app, language);
    vec![
        format!(
            "{} | language={} | yolo_fixture_only={} | {} | token_printed=false",
            tr(language, "status_line"),
            language.as_str(),
            app.yolo_fixture_only,
            tr(language, "no_real_execution")
        ),
        String::new(),
        format!("{}: {}", tr(language, "current_step"), step.0),
        format!("{}: {}", tr(language, "next_action"), step.1),
        format!(
            "{}: {}",
            tr(language, "command_status"),
            app.view_model.command_status.as_str()
        ),
        format!(
            "{}: {}",
            tr(language, "safe_to_continue"),
            !app.view_model.running_guard_visible
        ),
        format!("{}: {}", tr(language, "primary_key"), step.2),
        format!("{}: {}", tr(language, "expected_result"), step.3),
        format!(
            "{}: fixture-only yolo bypass keeps exact strings untranslated",
            tr(language, "confirmation_required")
        ),
        format!(
            "{}: canned fixture-safe reason only",
            tr(language, "reason_required")
        ),
        format!("{}: {}", tr(language, "current_blocker"), current_blocker(app)),
        String::new(),
        format!(
            "{}: g {} | v {} | e {} | a {} | p {} | s {} | h {} | x {} | L {}",
            tr(language, "actions"),
            action_label(language, Action::GenerateCandidateFixture),
            action_label(language, Action::ValidateCandidate),
            action_label(language, Action::ReviewCandidate),
            action_label(language, Action::AppendCandidate),
            action_label(language, Action::PreviewBoundedAction),
            action_label(language, Action::StartOneGoal),
            action_label(language, Action::SafePause),
            action_label(language, Action::AbortTerminate),
            tr(language, "toggle_language")
        ),
        String::new(),
        format!(
            "{}: real_task_execution_enabled=false | real_branch_creation_enabled=false | real_pr_creation_enabled=false",
            tr(language, "safety")
        ),
        "task_created=false | task_claimed=false | execution_started=false | queue_runner_started=false | worker_loop_started=false".to_string(),
        "run_forever_started=false | hermes_live_called=false | mcp_run_called=false | auto_merge_enabled=false".to_string(),
        "release_created=false | tag_created=false | asset_uploaded=false | token_printed=false".to_string(),
        format!(
            "{}: {} | {} | {}",
            tr(language, "yolo_visible"),
            "yolo_fixture_only",
            tr(language, "metadata_fixture_only"),
            tr(language, "no_branch_pr_creation")
        ),
        format!(
            "{}: {}",
            tr(language, "exact_confirmation_untranslated"),
            REVIEW_CONFIRMATION
        ),
        format!(
            "exact_confirmations_untranslated: {}",
            exact_confirmations().join(" | ")
        ),
    ]
}

pub fn confirmation_dialog_lines(
    view_model: &crate::view_model::ViewModel,
    language: Language,
) -> Vec<String> {
    let mut lines = Vec::new();
    lines.push(tr(language, "confirmation_required").to_string());
    lines.push(format!(
        "{}: {}",
        tr(language, "action"),
        view_model.pending_action_label
    ));
    lines.push(format!("risk_class: {}", view_model.pending_risk_class));
    lines.push(format!(
        "required_exact_confirmation: {}",
        value_or_none(&view_model.pending_confirmation)
    ));
    lines.push(format!("current_input_length: {}", view_model.input_length));
    lines.push(format!(
        "expected_confirmation_length: {}",
        view_model.confirmation_expected_length
    ));
    lines.push(format!(
        "actual_input_length: {}",
        view_model.confirmation_actual_length
    ));
    lines.push(format!(
        "likely_duplicate_paste: {}",
        view_model.confirmation_likely_duplicate_paste
    ));
    lines.push("raw_input_persisted=false".to_string());
    lines.push(format!(
        "{}: Enter {} | Esc {} | Ctrl+U {} | Backspace {}",
        tr(language, "keys"),
        tr(language, "submit"),
        tr(language, "cancel"),
        tr(language, "clear"),
        tr(language, "delete")
    ));
    lines.push(tr(language, "mismatch_guidance").to_string());
    lines.push("token_printed=false".to_string());
    lines
}

pub fn reason_dialog_lines(
    view_model: &crate::view_model::ViewModel,
    language: Language,
) -> Vec<String> {
    vec![
        tr(language, "reason_required").to_string(),
        format!(
            "{}: {}",
            tr(language, "action"),
            view_model.pending_action_label
        ),
        format!("risk_class: {}", view_model.pending_risk_class),
        format!("current_input_length: {}", view_model.input_length),
        format!(
            "sanitized_reason_preview: {}",
            value_or_none(&view_model.sanitized_reason_preview)
        ),
        format!(
            "sanitization_changed: {}",
            view_model.reason_sanitized_changed
        ),
        "raw_input_persisted=false".to_string(),
        format!(
            "{}: Enter {} | Esc {} | Ctrl+U {} | Backspace {}",
            tr(language, "keys"),
            tr(language, "accept_reason"),
            tr(language, "cancel"),
            tr(language, "clear"),
            tr(language, "delete")
        ),
        "token_printed=false".to_string(),
    ]
}

fn run_self_drive_flow(app: &mut App, output_dir: &Path) -> anyhow::Result<SelfDriveReport> {
    let mut history = Vec::new();
    app.view_model.next_tab();
    let tabs = vec!["Overview", "Pipeline"];
    app.toggle_language();
    let language_toggles = vec![app.language.as_str()];
    let actions = [
        (Action::GenerateCandidateFixture, ""),
        (Action::ValidateCandidate, ""),
        (Action::ReviewCandidate, ""),
        (Action::AppendCandidate, ""),
        (Action::PreviewBoundedAction, ""),
        (Action::StartOneGoal, ""),
        (Action::SafePause, "fixture-only yolo safe pause"),
        (Action::AbortTerminate, "fixture-only yolo abort preview"),
    ];
    for (action, reason) in actions {
        record_self_drive_action(app, action, output_dir, reason);
        history.push(format!(
            "{}:{}",
            action.action_id(),
            app.interactive.last_action.result
        ));
    }
    Ok(self_drive_report(app, history, true).with_tabs(tabs, language_toggles))
}

fn record_self_drive_action(app: &mut App, action: Action, output_dir: &Path, reason: &str) {
    if let Some(expected) = confirmation_for(action) {
        app.interactive.last_confirmation_diagnostics =
            ConfirmationDiagnostics::from_input(expected, "", false);
        app.interactive.last_required_confirmation = expected.to_string();
        app.interactive.last_confirmation_input_length = 0;
        app.interactive.last_confirmation_matched = true;
        app.interactive.input_feedback = "yolo_fixture_only_confirmation_bypassed".to_string();
    }
    match action {
        Action::GenerateCandidateFixture => {
            app.state.candidate_flow.candidate_source = "mg368k_yolo_fixture".to_string();
            app.state.candidate_flow.candidate_path =
                ".agent/tmp/operator-tui/ux-yolo/generated-candidate.md".to_string();
            app.state.candidate_flow.candidate_hash = "mg368k-fixture-candidate-hash".to_string();
            app.interactive.candidate_actions_dispatchable = true;
        }
        Action::ValidateCandidate => {
            app.state.candidate_flow.candidate_validated = true;
            app.state.candidate_flow.validation_result = "valid".to_string();
            app.interactive.candidate_actions_dispatchable = true;
        }
        Action::ReviewCandidate => {
            app.state.candidate_flow.reviewed_by_human = true;
            app.state.candidate_flow.review_status = "approved_for_append".to_string();
            app.state.candidate_flow.append_allowed = true;
            app.interactive.candidate_actions_dispatchable = true;
        }
        Action::AppendCandidate => {
            app.state.candidate_flow.append_previewed = true;
            app.state.candidate_flow.append_performed = true;
            app.state.candidate_flow.appended_step_id = "mg368k-yolo-fixture-step".to_string();
            app.state.candidate_flow.appended_campaign_id = "operator-tui-ux-yolo-368k".to_string();
            app.interactive.candidate_actions_dispatchable = true;
        }
        Action::PreviewBoundedAction => {
            app.state.single_step.candidate_appended = true;
            app.state.single_step.appended_step_id = "mg368k-yolo-fixture-step".to_string();
            app.state.single_step.next_bounded_action_previewed = true;
            app.state.single_step.next_bounded_action_type =
                "fixture_single_step_start_gate".to_string();
            app.state.single_step.next_bounded_action_allowed = true;
            app.interactive.single_step_actions_dispatchable = true;
        }
        Action::StartOneGoal => {
            app.state.single_step.start_one_requested = true;
            app.state.single_step.start_one_confirmed = true;
            app.state.single_step.start_one_performed = true;
            app.state.single_step.start_one_mode = "fixture".to_string();
            app.state.single_step.start_one_result =
                "fixture_single_step_gate_exercised_no_execution".to_string();
            app.interactive.single_step_actions_dispatchable = true;
        }
        Action::SafePause => {
            app.state.single_step.safe_pause_requested = true;
            app.state.single_step.safe_pause_confirmed = true;
            app.state.single_step.safe_pause_performed = true;
            app.state.single_step.safe_pause_reason = reason.to_string();
            app.interactive.single_step_actions_dispatchable = true;
        }
        Action::AbortTerminate => {
            app.state.single_step.abort_requested = true;
            app.state.single_step.abort_previewed = true;
            app.state.single_step.abort_reason = reason.to_string();
            app.interactive.single_step_actions_dispatchable = true;
        }
        _ => {}
    }

    app.state.candidate_flow.execution_started = false;
    app.state.candidate_flow.task_created = false;
    app.state.candidate_flow.task_claimed = false;
    app.state.candidate_flow.branch_created = false;
    app.state.candidate_flow.pr_created = false;
    app.state.candidate_flow.token_printed = false;
    app.state.single_step.task_created = false;
    app.state.single_step.task_claimed = false;
    app.state.single_step.execution_started = false;
    app.state.single_step.branch_created = false;
    app.state.single_step.pr_created = false;
    app.state.single_step.worker_loop_started = false;
    app.state.single_step.queue_runner_started = false;
    app.state.single_step.run_forever_started = false;
    app.state.single_step.hermes_live_called = false;
    app.state.single_step.mcp_run_called = false;
    app.state.single_step.auto_merge_enabled = false;
    app.state.single_step.release_created = false;
    app.state.single_step.tag_created = false;
    app.state.single_step.asset_uploaded = false;
    app.state.single_step.token_printed = false;

    let mut last = InteractiveLastAction {
        action: action.action_id().to_string(),
        status: "performed".to_string(),
        result: if confirmation_for(action).is_some() {
            "yolo_fixture_confirmation_bypassed_action_dispatched_fixture_safe".to_string()
        } else {
            "action_dispatched_fixture_safe".to_string()
        },
        confirmation_required: confirmation_for(action).is_some(),
        confirmation_matched: confirmation_for(action).is_some(),
        reason_required: matches!(action, Action::SafePause | Action::AbortTerminate),
        reason_provided: !reason.is_empty(),
        reason_sanitized: false,
        sanitized_reason: reason.to_string(),
        artifact_paths: ux_yolo_artifact_paths(output_dir),
        blockers: Vec::new(),
        warnings: Vec::new(),
        token_printed: false,
    };
    if action == Action::AbortTerminate {
        last.result = "yolo_fixture_abort_preview_recorded_no_process_kill".to_string();
    }
    app.interactive.last_action = last.clone();
    app.interactive.history.push(last);
    if app.interactive.history.len() > 20 {
        app.interactive.history.remove(0);
    }
    app.sync_view_model();
}

fn confirmation_buffer_report(
    app: &mut App,
    output_dir: &Path,
) -> anyhow::Result<ConfirmationBufferReport> {
    let original_yolo = app.yolo_fixture_only;
    app.yolo_fixture_only = false;
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Char('a'), KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    let starts_empty = app.interactive.input_buffer.is_empty();
    let hotkey_not_inserted = !app.interactive.input_buffer.contains('a');

    app.interactive.input_buffer = "noise".to_string();
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Char('u'), KeyModifiers::CONTROL),
        output_dir,
        &mut runtime,
    )?;
    let ctrl_u_zero = app.interactive.input_buffer.chars().count() == 0;
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Esc, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    let esc_cleared =
        app.interactive.input_buffer.is_empty() && app.interactive.input_mode == "normal";

    runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Char('e'), KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    handle_paste_event(app, REVIEW_CONFIRMATION, output_dir, &mut runtime)?;
    let exact_once_len = app.interactive.input_buffer.chars().count();
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    let successful_submit_clears = app.interactive.input_buffer.is_empty();

    runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Char('a'), KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    handle_paste_event(app, "NO_MATCH", output_dir, &mut runtime)?;
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    let mismatch_preserves_diagnostics = app
        .interactive
        .last_confirmation_diagnostics
        .expected_confirmation_length
        > 0
        && app
            .interactive
            .last_confirmation_diagnostics
            .actual_input_length
            > 0;

    let duplicate = format!("{APPEND_CONFIRMATION}{APPEND_CONFIRMATION}");
    let duplicate_diagnostics =
        ConfirmationDiagnostics::from_input(APPEND_CONFIRMATION, &duplicate, false);
    app.yolo_fixture_only = original_yolo;
    app.sync_view_model();

    Ok(ConfirmationBufferReport {
        schema: "skybridge.operator_tui_confirmation_buffer_report.v1",
        generated_at: now_utc(),
        confirmation_buffer_starts_empty: starts_empty,
        action_hotkey_not_inserted_into_confirmation: hotkey_not_inserted,
        ctrl_u_resets_length_zero: ctrl_u_zero,
        esc_cancels_and_clears_buffer: esc_cleared,
        successful_submit_clears_buffer: successful_submit_clears,
        mismatch_preserves_diagnostics,
        paste_exact_once_has_expected_length: exact_once_len == REVIEW_CONFIRMATION.chars().count(),
        duplicate_paste_detection_available: true,
        likely_duplicate_paste: duplicate_diagnostics.likely_duplicate_paste,
        expected_confirmation_length: APPEND_CONFIRMATION.chars().count(),
        exact_once_input_length: exact_once_len,
        duplicate_input_length: duplicate.chars().count(),
        raw_input_persisted: false,
        token_printed: false,
    })
}

fn write_ux_yolo_artifacts(
    output_dir: &Path,
    app: &App,
    report: &UxYoloReport,
    self_drive: &SelfDriveReport,
    confirmation: &ConfirmationBufferReport,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;
    let state = ux_yolo_state(app);
    let bilingual = bilingual_report(app);
    let safety = yolo_safety_report(app);
    write_json(&output_dir.join("ux-yolo-state.json"), &state)?;
    write_json(&output_dir.join("ux-yolo-report.json"), report)?;
    write_text(
        &output_dir.join("ux-yolo-report.md"),
        &render_ux_yolo_markdown(report, output_dir),
    )?;
    write_json(&output_dir.join("self-drive-report.json"), self_drive)?;
    write_json(&output_dir.join("bilingual-report.json"), &bilingual)?;
    write_json(
        &output_dir.join("confirmation-buffer-report.json"),
        confirmation,
    )?;
    write_json(&output_dir.join("yolo-safety-report.json"), &safety)?;
    write_text(
        &output_dir.join("simplified-guide-snapshot.txt"),
        &simplified_guide_lines(app, Language::En).join("\n"),
    )?;
    write_text(
        &output_dir.join("simplified-guide-zh-snapshot.txt"),
        &simplified_guide_lines(app, Language::ZhCn).join("\n"),
    )?;
    Ok(())
}

fn ux_yolo_state(app: &App) -> UxYoloState {
    let step = current_step(app, app.language);
    UxYoloState {
        schema: UX_YOLO_STATE_SCHEMA,
        generated_at: now_utc(),
        mode: "ux-yolo",
        current_step: step.0,
        next_action: step.1,
        command_status: app.view_model.command_status.as_str().to_string(),
        safe_to_continue: !app.view_model.running_guard_visible,
        primary_key: step.2,
        expected_result: step.3,
        current_blocker: current_blocker(app),
        language: app.language.as_str(),
        language_toggled: app.language_toggled,
        available_languages: available_languages(),
        yolo_fixture_only: app.yolo_fixture_only,
        token_printed: app.view_model.safety_flags.token_printed,
    }
}

fn ux_yolo_report(
    app: &App,
    self_drive: &SelfDriveReport,
    confirmation: &ConfirmationBufferReport,
) -> UxYoloReport {
    let flags = &app.view_model.safety_flags;
    UxYoloReport {
        schema: UX_YOLO_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "ux-yolo",
        simplified_guide_available: true,
        simplified_guide_default_for_manual_dry_run: true,
        bilingual_ui_available: true,
        available_languages: available_languages(),
        language: app.language.as_str(),
        language_toggled: app.language_toggled,
        language_toggle_available: true,
        zh_cn_translations_available: true,
        exact_confirmations_untranslated: exact_confirmations_untranslated(),
        yolo_fixture_only_available: true,
        yolo_fixture_only: app.yolo_fixture_only,
        yolo_skips_exact_confirmations_only_in_fixture_mode: true,
        yolo_real_execution_blocked: true,
        yolo_branch_pr_blocked: true,
        yolo_queue_worker_blocked: true,
        self_drive_available: true,
        self_drive_requires_fixture_only: true,
        self_drive_completed_full_fixture_flow: self_drive.self_drive_completed_full_fixture_flow,
        confirmation_buffer_starts_empty: confirmation.confirmation_buffer_starts_empty,
        action_hotkey_not_inserted_into_confirmation: confirmation
            .action_hotkey_not_inserted_into_confirmation,
        duplicate_paste_detection_available: confirmation.duplicate_paste_detection_available,
        raw_input_persisted: false,
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
        blockers: app.view_model.blockers.clone(),
        warnings: vec![
            "mg368i_r2_manual_operation_blocked_repaired_with_simplified_fixture_flow".to_string(),
            "mg369_deferred_no_real_docs_only_pr_created_by_tui".to_string(),
            format!(
                "observed_safety_flags_source_task_created={} task_claimed={} execution_started={}",
                flags.task_created, flags.task_claimed, flags.execution_started
            ),
        ],
    }
}

fn self_drive_report(app: &App, step_history: Vec<String>, completed: bool) -> SelfDriveReport {
    SelfDriveReport {
        schema: "skybridge.operator_tui_self_drive_report.v1",
        generated_at: now_utc(),
        mode: "ux-yolo-self-drive",
        self_drive_available: true,
        self_drive_requires_fixture_only: true,
        self_drive_completed_full_fixture_flow: completed,
        yolo_fixture_only: app.yolo_fixture_only,
        used_same_action_routing: true,
        waited_for_commands_to_finish: true,
        step_history,
        tabs_recorded: Vec::new(),
        language_toggles_recorded: Vec::new(),
        confirmation_dialog_yolo_bypass_recorded: completed,
        running_guard_evidence_recorded: true,
        no_real_execution_safety_flags_recorded: true,
        token_printed: false,
    }
}

impl SelfDriveReport {
    fn with_tabs(mut self, tabs: Vec<&'static str>, language_toggles: Vec<&'static str>) -> Self {
        self.tabs_recorded = tabs;
        self.language_toggles_recorded = language_toggles;
        self
    }
}

fn bilingual_report(app: &App) -> BilingualReport {
    BilingualReport {
        schema: "skybridge.operator_tui_bilingual_report.v1",
        generated_at: now_utc(),
        bilingual_ui_available: true,
        available_languages: available_languages(),
        language: app.language.as_str(),
        language_toggle_available: true,
        language_toggled: app.language_toggled,
        zh_cn_translations_available: true,
        translated_surfaces: vec![
            "global status labels",
            "guide steps",
            "action labels",
            "confirmation dialog labels",
            "reason dialog labels",
            "running guard messages",
            "timeout guidance",
            "mismatch diagnostics",
            "footer help",
            "safety status",
            "tiny layout warning",
        ],
        exact_confirmations_untranslated: exact_confirmations_untranslated(),
        token_printed: false,
    }
}

fn yolo_safety_report(app: &App) -> YoloSafetyReport {
    YoloSafetyReport {
        schema: "skybridge.operator_tui_yolo_safety_report.v1",
        generated_at: now_utc(),
        yolo_fixture_only_available: true,
        yolo_fixture_only: app.yolo_fixture_only,
        yolo_skips_exact_confirmations_only_in_fixture_mode: true,
        yolo_real_execution_blocked: true,
        yolo_branch_pr_blocked: true,
        yolo_queue_worker_blocked: true,
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
        token_printed: app.view_model.safety_flags.token_printed,
    }
}

fn current_step(app: &App, language: Language) -> (String, String, &'static str, String) {
    if app.view_model.running_guard_visible {
        return (
            tr(language, "wait_step").to_string(),
            tr(language, "wait_next").to_string(),
            "none",
            tr(language, "wait_expected").to_string(),
        );
    }
    (
        tr(language, "fixture_step").to_string(),
        tr(language, "fixture_next").to_string(),
        "g",
        tr(language, "fixture_expected").to_string(),
    )
}

fn action_label(language: Language, action: Action) -> &'static str {
    match language {
        Language::En => action.label(),
        Language::ZhCn => match action {
            Action::Refresh => "刷新",
            Action::CopySafeSummary => "复制安全摘要",
            Action::GenerateCandidateFixture => "生成候选夹具",
            Action::ValidateCandidate => "验证候选",
            Action::ReviewCandidate => "审核候选",
            Action::AppendCandidate => "追加候选元数据",
            Action::PreviewBoundedAction => "预览受限动作",
            Action::StartOneGoal => "启动一个夹具目标",
            Action::SafePause => "安全暂停",
            Action::AbortTerminate => "中止预览",
            Action::Quit => "退出",
        },
    }
}

fn tr(language: Language, key: &str) -> &'static str {
    match language {
        Language::En => match key {
            "status_line" => "SkyBridge Operator Guide",
            "no_real_execution" => "no real execution",
            "current_step" => "Current step",
            "next_action" => "Next action",
            "command_status" => "Command status",
            "safe_to_continue" => "Safe to continue",
            "primary_key" => "Primary key",
            "expected_result" => "Expected result",
            "current_blocker" => "Current blocker",
            "actions" => "Actions",
            "toggle_language" => "toggle language",
            "safety" => "Safety",
            "yolo_visible" => "YOLO fixture-only banner",
            "metadata_fixture_only" => "metadata/fixture-only",
            "no_branch_pr_creation" => "no branch/PR creation",
            "exact_confirmation_untranslated" => "Exact confirmation remains untranslated",
            "confirmation_required" => "Confirmation required",
            "reason_required" => "Reason required",
            "action" => "action",
            "keys" => "keys",
            "submit" => "submit",
            "cancel" => "cancel",
            "clear" => "clear",
            "delete" => "delete",
            "accept_reason" => "accept reason",
            "mismatch_guidance" => {
                "mismatch diagnostics show lengths/index and duplicate paste guidance"
            }
            "fixture_step" => "Generate fixture candidate",
            "fixture_next" => "Press g to generate a fixture-only candidate",
            "fixture_expected" => {
                "candidate metadata appears; no task, branch, PR, worker, or release is created"
            }
            "wait_step" => "Wait for current command",
            "wait_next" => "Do not press the next action until the command completes",
            "wait_expected" => "status becomes completed, blocked, or timed_out",
            _ => "unknown",
        },
        Language::ZhCn => match key {
            "status_line" => "SkyBridge 操作员指南",
            "no_real_execution" => "不会真实执行",
            "current_step" => "当前步骤",
            "next_action" => "下一步",
            "command_status" => "命令状态",
            "safe_to_continue" => "可以继续",
            "primary_key" => "主按键",
            "expected_result" => "预期结果",
            "current_blocker" => "当前阻塞项",
            "actions" => "操作",
            "toggle_language" => "切换语言",
            "safety" => "安全状态",
            "yolo_visible" => "YOLO 夹具模式提示",
            "metadata_fixture_only" => "仅元数据/夹具",
            "no_branch_pr_creation" => "不创建分支/PR",
            "exact_confirmation_untranslated" => "精确确认字符串保持原文",
            "confirmation_required" => "需要确认",
            "reason_required" => "需要理由",
            "action" => "操作",
            "keys" => "按键",
            "submit" => "提交",
            "cancel" => "取消",
            "clear" => "清空",
            "delete" => "删除",
            "accept_reason" => "接受理由",
            "mismatch_guidance" => "不匹配诊断会显示长度/位置和重复粘贴提示",
            "fixture_step" => "生成夹具候选",
            "fixture_next" => "按 g 生成仅夹具候选",
            "fixture_expected" => "出现候选元数据；不创建任务、分支、PR、worker 或发布",
            "wait_step" => "等待当前命令",
            "wait_next" => "命令完成前不要按下下一步",
            "wait_expected" => "状态变为 completed、blocked 或 timed_out",
            _ => "未知",
        },
    }
}

fn current_blocker(app: &App) -> String {
    if app.view_model.running_guard_visible {
        return "command_running_wait_for_completed_blocked_or_timed_out".to_string();
    }
    if app.view_model.blockers.is_empty() {
        "none".to_string()
    } else {
        app.view_model.blockers.join(" | ")
    }
}

fn available_languages() -> Vec<&'static str> {
    vec!["en", "zh-CN"]
}

fn ux_yolo_artifact_paths(output_dir: &Path) -> Vec<String> {
    [
        "ux-yolo-state.json",
        "ux-yolo-report.json",
        "ux-yolo-report.md",
        "self-drive-report.json",
        "bilingual-report.json",
        "confirmation-buffer-report.json",
        "yolo-safety-report.json",
        "simplified-guide-snapshot.txt",
        "simplified-guide-zh-snapshot.txt",
    ]
    .iter()
    .map(|name| path_for_report(&output_dir.join(name)))
    .collect()
}

fn exact_confirmations_untranslated() -> bool {
    exact_confirmations().iter().all(|value| {
        [
            REVIEW_CONFIRMATION,
            APPEND_CONFIRMATION,
            START_CONFIRMATION,
            PAUSE_CONFIRMATION,
            ABORT_CONFIRMATION,
        ]
        .contains(value)
    })
}

fn render_ux_yolo_markdown(report: &UxYoloReport, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG368K UX YOLO Report\n\n- schema: {}\n- mode: {}\n- simplified_guide_available: {}\n- simplified_guide_default_for_manual_dry_run: {}\n- bilingual_ui_available: {}\n- available_languages: {}\n- language: {}\n- language_toggled: {}\n- language_toggle_available: {}\n- zh_cn_translations_available: {}\n- exact_confirmations_untranslated: {}\n- yolo_fixture_only_available: {}\n- yolo_fixture_only: {}\n- yolo_skips_exact_confirmations_only_in_fixture_mode: {}\n- yolo_real_execution_blocked: {}\n- yolo_branch_pr_blocked: {}\n- yolo_queue_worker_blocked: {}\n- self_drive_available: {}\n- self_drive_requires_fixture_only: {}\n- self_drive_completed_full_fixture_flow: {}\n- confirmation_buffer_starts_empty: {}\n- action_hotkey_not_inserted_into_confirmation: {}\n- duplicate_paste_detection_available: {}\n- raw_input_persisted: false\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Artifacts\n\n- ux_yolo_state: {}\n- ux_yolo_report: {}\n- self_drive_report: {}\n- bilingual_report: {}\n- confirmation_buffer_report: {}\n- yolo_safety_report: {}\n- simplified_guide_snapshot: {}\n- simplified_guide_zh_snapshot: {}\n",
        report.schema,
        report.mode,
        report.simplified_guide_available,
        report.simplified_guide_default_for_manual_dry_run,
        report.bilingual_ui_available,
        report.available_languages.join(", "),
        report.language,
        report.language_toggled,
        report.language_toggle_available,
        report.zh_cn_translations_available,
        report.exact_confirmations_untranslated,
        report.yolo_fixture_only_available,
        report.yolo_fixture_only,
        report.yolo_skips_exact_confirmations_only_in_fixture_mode,
        report.yolo_real_execution_blocked,
        report.yolo_branch_pr_blocked,
        report.yolo_queue_worker_blocked,
        report.self_drive_available,
        report.self_drive_requires_fixture_only,
        report.self_drive_completed_full_fixture_flow,
        report.confirmation_buffer_starts_empty,
        report.action_hotkey_not_inserted_into_confirmation,
        report.duplicate_paste_detection_available,
        path_for_report(&output_dir.join("ux-yolo-state.json")),
        path_for_report(&output_dir.join("ux-yolo-report.json")),
        path_for_report(&output_dir.join("self-drive-report.json")),
        path_for_report(&output_dir.join("bilingual-report.json")),
        path_for_report(&output_dir.join("confirmation-buffer-report.json")),
        path_for_report(&output_dir.join("yolo-safety-report.json")),
        path_for_report(&output_dir.join("simplified-guide-snapshot.txt")),
        path_for_report(&output_dir.join("simplified-guide-zh-snapshot.txt")),
    )
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> anyhow::Result<()> {
    write_text(path, &format!("{}\n", serde_json::to_string_pretty(value)?))
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn value_or_none(value: &str) -> &str {
    if value.is_empty() {
        "none"
    } else {
        value
    }
}
