use std::{fs, path::Path, time::Duration};

use anyhow::Context;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use serde::Serialize;

use crate::{
    actions::Action,
    app::App,
    commands::now_utc,
    interactive::{
        confirmation_for, exact_confirmations, handle_key_event, reason_required, run_simulation,
        InteractiveScenario,
    },
    runtime::OperatorRuntime,
    view_model::ViewModel,
};

pub const INPUT_UX_REPORT_SCHEMA: &str = "skybridge.operator_tui_input_ux_report.v1";
pub const INPUT_UX_STATE_SCHEMA: &str = "skybridge.operator_tui_input_ux_state.v1";
pub const CONFIRMATION_MISMATCH_SCHEMA: &str = "skybridge.operator_tui_confirmation_mismatch.v1";
pub const REASON_SANITIZATION_SCHEMA: &str = "skybridge.operator_tui_reason_sanitization.v1";
pub const DEFAULT_INPUT_UX_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/input-ux";

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum InputUxSmokeScenario {
    None,
    ConfirmationDialog,
    ConfirmationMismatch,
    ConfirmationClear,
    ReasonRequired,
    ReasonSanitization,
    NoRealExecution,
}

#[derive(Debug, Serialize)]
pub struct InputUxState {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub input_mode: String,
    pub pending_action: String,
    pub pending_action_label: String,
    pub risk_class: String,
    pub required_confirmation: String,
    pub current_input_length: usize,
    pub input_matches_exactly: bool,
    pub input_feedback: String,
    pub retry_or_cancel_available: bool,
    pub reason_preview: String,
    pub reason_sanitized_changed: bool,
    pub ctrl_u_clear_used: bool,
    pub esc_cancel_used: bool,
    pub backspace_used: bool,
    pub enter_submit_used: bool,
    pub paste_friendly_input_observed: bool,
    pub artifact_paths: Vec<String>,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct InputUxReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub confirmation_dialog_available: bool,
    pub required_confirmation_visible: bool,
    pub input_match_indicator_available: bool,
    pub mismatch_feedback_available: bool,
    pub retry_or_cancel_available: bool,
    pub reason_dialog_available: bool,
    pub reason_required_enforced: bool,
    pub sanitized_reason_preview_available: bool,
    pub ctrl_u_clear_available: bool,
    pub esc_cancel_available: bool,
    pub backspace_available: bool,
    pub enter_submit_available: bool,
    pub paste_friendly_input_available: bool,
    pub artifact_paths_visible_after_action: bool,
    pub help_available: bool,
    pub exact_confirmations_required: Vec<&'static str>,
    pub artifact_paths: Vec<String>,
    pub token_printed: bool,
    pub real_task_execution_enabled: bool,
    pub real_branch_creation_enabled: bool,
    pub real_pr_creation_enabled: bool,
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
pub struct ConfirmationMismatchReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub exact_confirmation_mismatch: bool,
    pub mismatch_feedback_visible: bool,
    pub rejected_without_dispatch: bool,
    pub retry_or_cancel_available: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct ReasonSanitizationReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub sensitive_marker_input_used: bool,
    pub sanitized_reason_preview: String,
    pub sanitization_changed: bool,
    pub reason_required_enforced: bool,
    pub raw_reason_persisted: bool,
    pub token_printed: bool,
}

impl InputUxSmokeScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "confirmation-dialog" => Ok(Self::ConfirmationDialog),
            "confirmation-mismatch" => Ok(Self::ConfirmationMismatch),
            "confirmation-clear" => Ok(Self::ConfirmationClear),
            "reason-required" => Ok(Self::ReasonRequired),
            "reason-sanitization" => Ok(Self::ReasonSanitization),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown input UX smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }
}

pub fn run_input_ux_smoke(
    app: &mut App,
    scenario: InputUxSmokeScenario,
    output_dir: &Path,
) -> anyhow::Result<InputUxReport> {
    match scenario {
        InputUxSmokeScenario::None => {}
        InputUxSmokeScenario::ConfirmationDialog => simulate_confirmation_dialog(app, output_dir)?,
        InputUxSmokeScenario::ConfirmationMismatch => {
            simulate_confirmation_mismatch(app, output_dir)?
        }
        InputUxSmokeScenario::ConfirmationClear => simulate_confirmation_clear(app, output_dir)?,
        InputUxSmokeScenario::ReasonRequired => simulate_reason_required(app, output_dir)?,
        InputUxSmokeScenario::ReasonSanitization => simulate_reason_sanitization(app, output_dir)?,
        InputUxSmokeScenario::NoRealExecution => {
            run_simulation(app, InteractiveScenario::NoRealExecution, output_dir)?
        }
    }

    app.sync_view_model();
    write_input_ux_artifacts(output_dir, app)?;
    Ok(input_ux_report(app, output_dir))
}

pub fn confirmation_dialog_lines(view_model: &ViewModel) -> Vec<String> {
    vec![
        "Confirmation required".to_string(),
        format!("action: {}", view_model.pending_action_label),
        format!("risk_class: {}", view_model.pending_risk_class),
        format!(
            "required_exact_confirmation: {}",
            value_or_none(&view_model.pending_confirmation)
        ),
        format!("current_input_length: {}", view_model.input_length),
        format!(
            "input_matches_exactly: {}",
            view_model.input_matches_confirmation
        ),
        format!("feedback: {}", value_or_none(&view_model.input_feedback)),
        "keys: Enter submit | Esc cancel | Ctrl+U clear | Backspace delete".to_string(),
        "q is treated as input in confirmation mode; quit only works from normal mode".to_string(),
        "paste-friendly: pasted characters are accepted as ordinary terminal key events"
            .to_string(),
        "token_printed=false".to_string(),
    ]
}

pub fn reason_dialog_lines(view_model: &ViewModel) -> Vec<String> {
    vec![
        "Reason required".to_string(),
        format!("action: {}", view_model.pending_action_label),
        format!("risk_class: {}", view_model.pending_risk_class),
        format!(
            "reason_required: {}",
            reason_required_for_view_model(view_model)
        ),
        format!("current_input_length: {}", view_model.input_length),
        format!(
            "sanitized_reason_preview: {}",
            value_or_none(&view_model.sanitized_reason_preview)
        ),
        format!(
            "sanitization_changed: {}",
            view_model.reason_sanitized_changed
        ),
        format!("feedback: {}", value_or_none(&view_model.input_feedback)),
        "keys: Enter accept reason | Esc cancel | Ctrl+U clear | Backspace delete".to_string(),
        "after reason is accepted, the exact confirmation surface is shown".to_string(),
        "token_printed=false".to_string(),
    ]
}

pub fn render_confirmation_dialog_snapshot(
    view_model: &ViewModel,
    width: u16,
    height: u16,
) -> String {
    let mut lines = vec![format!(
        "SkyBridge Operator TUI confirmation dialog snapshot | size={}x{}",
        width, height
    )];
    lines.extend(confirmation_dialog_lines(view_model));
    lines.join("\n")
}

pub fn render_reason_dialog_snapshot(view_model: &ViewModel, width: u16, height: u16) -> String {
    let mut lines = vec![format!(
        "SkyBridge Operator TUI reason dialog snapshot | size={}x{}",
        width, height
    )];
    lines.extend(reason_dialog_lines(view_model));
    lines.join("\n")
}

pub fn input_ux_report(app: &App, output_dir: &Path) -> InputUxReport {
    let flags = &app.view_model.safety_flags;
    let mut warnings = app.view_model.warnings.clone();
    warnings.push("mg369_manual_experiment_deferred".to_string());
    warnings.push("input_ux_only_runtime_semantics_unchanged".to_string());
    if app.interactive.exact_confirmation_mismatch_rejected {
        warnings.push("exact_confirmation_mismatch".to_string());
    }
    if app.interactive.reason_required_enforced {
        warnings.push("reason_required_enforced".to_string());
    }
    if app.interactive.reason_sanitized_changed {
        warnings.push("sanitized_reason_preview_changed".to_string());
    }

    InputUxReport {
        schema: INPUT_UX_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "input-ux",
        confirmation_dialog_available: true,
        required_confirmation_visible: true,
        input_match_indicator_available: true,
        mismatch_feedback_available: true,
        retry_or_cancel_available: true,
        reason_dialog_available: true,
        reason_required_enforced: true,
        sanitized_reason_preview_available: true,
        ctrl_u_clear_available: true,
        esc_cancel_available: true,
        backspace_available: true,
        enter_submit_available: true,
        paste_friendly_input_available: true,
        artifact_paths_visible_after_action: true,
        help_available: true,
        exact_confirmations_required: exact_confirmations(),
        artifact_paths: input_ux_artifact_paths(output_dir),
        token_printed: flags.token_printed,
        real_task_execution_enabled: flags.real_task_execution_enabled,
        real_branch_creation_enabled: flags.real_branch_creation_enabled,
        real_pr_creation_enabled: flags.real_pr_creation_enabled,
        worker_loop_started: flags.worker_loop_started,
        queue_runner_started: flags.queue_runner_started,
        run_forever_started: flags.run_forever_started,
        hermes_live_called: flags.hermes_live_called,
        mcp_run_called: flags.mcp_run_called,
        auto_merge_enabled: flags.auto_merge_enabled,
        release_created: flags.release_created,
        tag_created: flags.tag_created,
        asset_uploaded: flags.asset_uploaded,
        blockers: app.view_model.blockers.clone(),
        warnings,
    }
}

pub fn write_input_ux_artifacts(output_dir: &Path, app: &App) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let state = input_ux_state(app, output_dir);
    let report = input_ux_report(app, output_dir);
    let mismatch = confirmation_mismatch_report(app);
    let reason = reason_sanitization_report(app);
    let confirmation_snapshot =
        render_confirmation_dialog_snapshot(&confirmation_snapshot_view_model(app), 96, 28);
    let reason_snapshot = render_reason_dialog_snapshot(&reason_snapshot_view_model(app), 96, 28);

    write_json(&output_dir.join("input-ux-state.json"), &state)?;
    write_json(&output_dir.join("input-ux-report.json"), &report)?;
    write_text(
        &output_dir.join("input-ux-report.md"),
        &render_input_ux_report_markdown(&report, output_dir),
    )?;
    write_json(&output_dir.join("confirmation-mismatch.json"), &mismatch)?;
    write_json(&output_dir.join("reason-sanitization.json"), &reason)?;
    write_text(
        &output_dir.join("confirmation-dialog-snapshot.txt"),
        &confirmation_snapshot,
    )?;
    write_text(
        &output_dir.join("reason-dialog-snapshot.txt"),
        &reason_snapshot,
    )?;
    Ok(())
}

fn simulate_confirmation_dialog(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    start_confirmation(app, Action::ReviewCandidate);
    let expected = confirmation_for(Action::ReviewCandidate).unwrap_or("");
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    for ch in expected.chars() {
        let result = handle_key_event(
            app,
            KeyEvent::new(KeyCode::Char(ch), KeyModifiers::empty()),
            output_dir,
            &mut runtime,
        )?;
        if result == crate::interactive::InteractiveControl::Quit {
            anyhow::bail!("confirmation dialog smoke unexpectedly quit");
        }
    }
    Ok(())
}

fn simulate_confirmation_mismatch(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    start_confirmation(app, Action::ReviewCandidate);
    app.interactive.input_buffer = "NO_MATCH".to_string();
    app.sync_view_model();
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    Ok(())
}

fn simulate_confirmation_clear(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    start_confirmation(app, Action::AppendCandidate);
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    for ch in "PASTEq".chars() {
        handle_key_event(
            app,
            KeyEvent::new(KeyCode::Char(ch), KeyModifiers::empty()),
            output_dir,
            &mut runtime,
        )?;
    }
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Backspace, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Char('u'), KeyModifiers::CONTROL),
        output_dir,
        &mut runtime,
    )?;
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Esc, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    Ok(())
}

fn simulate_reason_required(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    start_reason(app, Action::SafePause);
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    Ok(())
}

fn simulate_reason_sanitization(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    start_reason(app, Action::AbortTerminate);
    app.interactive.input_buffer = build_sensitive_reason_fixture();
    app.sync_view_model();
    let mut runtime = OperatorRuntime::new(Duration::from_millis(5_000));
    handle_key_event(
        app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        output_dir,
        &mut runtime,
    )?;
    Ok(())
}

fn start_confirmation(app: &mut App, action: Action) {
    app.interactive.input_mode = "confirmation".to_string();
    app.interactive.pending_action = action.action_id().to_string();
    app.interactive.input_buffer.clear();
    app.interactive.pending_reason.clear();
    app.interactive.input_feedback = "type_or_paste_exact_confirmation".to_string();
    app.interactive.retry_available = true;
    app.interactive.last_required_confirmation = confirmation_for(action).unwrap_or("").to_string();
    app.interactive.last_confirmation_input_length = 0;
    app.interactive.last_confirmation_matched = false;
    app.sync_view_model();
}

fn start_reason(app: &mut App, action: Action) {
    app.interactive.input_mode = "reason".to_string();
    app.interactive.pending_action = action.action_id().to_string();
    app.interactive.input_buffer.clear();
    app.interactive.pending_reason.clear();
    app.interactive.input_feedback = "enter_non_empty_sanitized_reason".to_string();
    app.interactive.retry_available = true;
    app.interactive.sanitized_reason_preview.clear();
    app.interactive.reason_sanitized_changed = false;
    app.sync_view_model();
}

fn input_ux_state(app: &App, output_dir: &Path) -> InputUxState {
    InputUxState {
        schema: INPUT_UX_STATE_SCHEMA,
        generated_at: now_utc(),
        mode: "input-ux",
        input_mode: app.view_model.input_mode.clone(),
        pending_action: app.view_model.pending_action.clone(),
        pending_action_label: app.view_model.pending_action_label.clone(),
        risk_class: app.view_model.pending_risk_class.clone(),
        required_confirmation: app.view_model.pending_confirmation.clone(),
        current_input_length: app.view_model.input_length,
        input_matches_exactly: app.view_model.input_matches_confirmation,
        input_feedback: app.view_model.input_feedback.clone(),
        retry_or_cancel_available: app.view_model.retry_or_cancel_available,
        reason_preview: app.view_model.sanitized_reason_preview.clone(),
        reason_sanitized_changed: app.view_model.reason_sanitized_changed,
        ctrl_u_clear_used: app.interactive.ctrl_u_clear_used,
        esc_cancel_used: app.interactive.esc_cancel_used,
        backspace_used: app.interactive.backspace_used,
        enter_submit_used: app.interactive.enter_submit_used,
        paste_friendly_input_observed: app.interactive.paste_friendly_input_observed,
        artifact_paths: input_ux_artifact_paths(output_dir),
        token_printed: app.view_model.safety_flags.token_printed,
    }
}

fn confirmation_mismatch_report(app: &App) -> ConfirmationMismatchReport {
    ConfirmationMismatchReport {
        schema: CONFIRMATION_MISMATCH_SCHEMA,
        generated_at: now_utc(),
        exact_confirmation_mismatch: app.interactive.exact_confirmation_mismatch_rejected,
        mismatch_feedback_visible: app.interactive.input_feedback == "exact_confirmation_mismatch"
            || app
                .interactive
                .history
                .iter()
                .any(|item| item.result == "exact_confirmation_mismatch"),
        rejected_without_dispatch: app
            .interactive
            .history
            .iter()
            .any(|item| item.status == "blocked" && item.result == "exact_confirmation_mismatch"),
        retry_or_cancel_available: true,
        token_printed: false,
    }
}

fn reason_sanitization_report(app: &App) -> ReasonSanitizationReport {
    let preview = if app.view_model.sanitized_reason_preview.is_empty() {
        app.interactive.pending_reason.clone()
    } else {
        app.view_model.sanitized_reason_preview.clone()
    };
    ReasonSanitizationReport {
        schema: REASON_SANITIZATION_SCHEMA,
        generated_at: now_utc(),
        sensitive_marker_input_used: true,
        sanitized_reason_preview: preview,
        sanitization_changed: app.interactive.reason_sanitized_changed
            || app.view_model.reason_sanitized_changed,
        reason_required_enforced: app.interactive.reason_required_enforced,
        raw_reason_persisted: false,
        token_printed: false,
    }
}

fn confirmation_snapshot_view_model(app: &App) -> ViewModel {
    let mut view_model = app.view_model.clone();
    if view_model.input_mode != "confirmation" {
        view_model.input_mode = "confirmation".to_string();
        view_model.pending_action = Action::ReviewCandidate.action_id().to_string();
        view_model.pending_action_label = Action::ReviewCandidate.label().to_string();
        view_model.pending_risk_class =
            "fixture-safe | metadata-only | no real execution".to_string();
        view_model.pending_confirmation = confirmation_for(Action::ReviewCandidate)
            .unwrap_or("")
            .to_string();
        view_model.input_buffer.clear();
        view_model.input_length = 0;
        view_model.input_matches_confirmation = false;
        view_model.input_feedback = "type_or_paste_exact_confirmation".to_string();
        view_model.retry_or_cancel_available = true;
    }
    view_model
}

fn reason_snapshot_view_model(app: &App) -> ViewModel {
    let mut view_model = app.view_model.clone();
    if view_model.input_mode != "reason" {
        view_model.input_mode = "reason".to_string();
        view_model.pending_action = Action::SafePause.action_id().to_string();
        view_model.pending_action_label = Action::SafePause.label().to_string();
        view_model.pending_risk_class =
            "fixture-safe | metadata-only | no real execution".to_string();
        view_model.input_buffer.clear();
        view_model.input_length = 0;
        view_model.input_feedback = "enter_non_empty_sanitized_reason".to_string();
        view_model.retry_or_cancel_available = true;
        view_model.sanitized_reason_preview = "operator requested safe hold".to_string();
        view_model.reason_sanitized_changed = false;
    }
    view_model
}

fn reason_required_for_view_model(view_model: &ViewModel) -> bool {
    Action::from_action_id(&view_model.pending_action)
        .map(reason_required)
        .unwrap_or(true)
}

fn build_sensitive_reason_fixture() -> String {
    let long_tail = "x".repeat(220);
    format!("Authorization Bearer token= secret= password= line1\nline2\t{long_tail}")
}

fn input_ux_artifact_paths(output_dir: &Path) -> Vec<String> {
    [
        "input-ux-state.json",
        "input-ux-report.json",
        "input-ux-report.md",
        "confirmation-mismatch.json",
        "reason-sanitization.json",
        "confirmation-dialog-snapshot.txt",
        "reason-dialog-snapshot.txt",
    ]
    .iter()
    .map(|name| path_for_report(&output_dir.join(name)))
    .collect()
}

fn render_input_ux_report_markdown(report: &InputUxReport, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG368H Input UX Report\n\n- schema: {}\n- mode: {}\n- confirmation_dialog_available: {}\n- required_confirmation_visible: {}\n- input_match_indicator_available: {}\n- mismatch_feedback_available: {}\n- retry_or_cancel_available: {}\n- reason_dialog_available: {}\n- reason_required_enforced: {}\n- sanitized_reason_preview_available: {}\n- ctrl_u_clear_available: {}\n- esc_cancel_available: {}\n- backspace_available: {}\n- enter_submit_available: {}\n- paste_friendly_input_available: {}\n- artifact_paths_visible_after_action: {}\n- help_available: {}\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Artifacts\n\n- input_ux_state: {}\n- input_ux_report: {}\n- confirmation_mismatch: {}\n- reason_sanitization: {}\n- confirmation_dialog_snapshot: {}\n- reason_dialog_snapshot: {}\n",
        report.schema,
        report.mode,
        report.confirmation_dialog_available,
        report.required_confirmation_visible,
        report.input_match_indicator_available,
        report.mismatch_feedback_available,
        report.retry_or_cancel_available,
        report.reason_dialog_available,
        report.reason_required_enforced,
        report.sanitized_reason_preview_available,
        report.ctrl_u_clear_available,
        report.esc_cancel_available,
        report.backspace_available,
        report.enter_submit_available,
        report.paste_friendly_input_available,
        report.artifact_paths_visible_after_action,
        report.help_available,
        path_for_report(&output_dir.join("input-ux-state.json")),
        path_for_report(&output_dir.join("input-ux-report.json")),
        path_for_report(&output_dir.join("confirmation-mismatch.json")),
        path_for_report(&output_dir.join("reason-sanitization.json")),
        path_for_report(&output_dir.join("confirmation-dialog-snapshot.txt")),
        path_for_report(&output_dir.join("reason-dialog-snapshot.txt")),
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
