use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::{
    actions::Action,
    app::{App, Cli},
    candidate::{CandidateAction, APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    collect::StateMode,
    commands::{CommandStatus, OperatorCommand, OperatorCommandResult},
    model::ActionStatus,
    render::PANELS,
    runtime::{EnqueueOutcome, OperatorRuntime, RuntimeDispatchOptions},
    single_step::{SingleStepAction, ABORT_CONFIRMATION, PAUSE_CONFIRMATION, START_CONFIRMATION},
};

pub const INTERACTIVE_REPORT_SCHEMA: &str =
    "skybridge.operator_tui_interactive_unblocker_report.v1";
pub const DEFAULT_INTERACTIVE_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/interactive-unblocker";
pub const MG369_MANUAL_GATE_MESSAGE: &str = "MG369 manual experiment can now be attempted by Jerry. This TUI supports confirmation-gated interactive actions, but real docs-only PR creation must be authorized and reported in MG369.";

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum InteractiveScenario {
    None,
    Actions,
    ConfirmationReject,
    ReasonRequired,
    CandidateDispatch,
    SingleStepDispatch,
    NoRealExecution,
}

impl InteractiveScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "actions" => Ok(Self::Actions),
            "confirmation-reject" => Ok(Self::ConfirmationReject),
            "reason-required" => Ok(Self::ReasonRequired),
            "candidate-dispatch" => Ok(Self::CandidateDispatch),
            "single-step-dispatch" => Ok(Self::SingleStepDispatch),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown interactive unblocker smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteractiveState {
    pub selected_action_index: usize,
    pub input_mode: String,
    pub pending_action: String,
    pub input_buffer: String,
    pub pending_reason: String,
    pub input_feedback: String,
    pub retry_available: bool,
    pub last_required_confirmation: String,
    pub last_confirmation_input_length: usize,
    pub last_confirmation_matched: bool,
    pub sanitized_reason_preview: String,
    pub reason_sanitized_changed: bool,
    pub ctrl_u_clear_used: bool,
    pub esc_cancel_used: bool,
    pub backspace_used: bool,
    pub enter_submit_used: bool,
    pub paste_friendly_input_observed: bool,
    pub last_action: InteractiveLastAction,
    pub history: Vec<InteractiveLastAction>,
    pub exact_confirmation_mismatch_rejected: bool,
    pub reason_required_enforced: bool,
    pub sanitized_reason_enforced: bool,
    pub candidate_actions_dispatchable: bool,
    pub single_step_actions_dispatchable: bool,
    pub manual_gate_written: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteractiveLastAction {
    pub action: String,
    pub status: String,
    pub result: String,
    pub confirmation_required: bool,
    pub confirmation_matched: bool,
    pub reason_required: bool,
    pub reason_provided: bool,
    pub reason_sanitized: bool,
    pub sanitized_reason: String,
    pub artifact_paths: Vec<String>,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
    pub token_printed: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct InteractiveReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub interactive_loop_available: bool,
    pub keyboard_actions_registered: bool,
    pub keyboard_actions: Vec<&'static str>,
    pub confirmation_input_available: bool,
    pub reason_input_available: bool,
    pub candidate_actions_dispatchable: bool,
    pub single_step_actions_dispatchable: bool,
    pub exact_confirmations_required: Vec<&'static str>,
    pub exact_confirmation_mismatch_rejected: bool,
    pub reason_required_enforced: bool,
    pub sanitized_reason_enforced: bool,
    pub manual_gate_written: bool,
    pub last_action: InteractiveLastAction,
    pub action_history: Vec<InteractiveLastAction>,
    pub active_actions: Vec<ActionStatus>,
    pub panels_rendered: Vec<&'static str>,
    pub artifact_paths: Vec<String>,
    pub real_task_execution_enabled: bool,
    pub real_branch_creation_enabled: bool,
    pub real_pr_creation_enabled: bool,
    pub queue_runner_started: bool,
    pub worker_loop_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub token_printed: bool,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum InteractiveControl {
    Continue,
    Quit,
}

impl Default for InteractiveState {
    fn default() -> Self {
        Self {
            selected_action_index: 0,
            input_mode: "normal".to_string(),
            pending_action: String::new(),
            input_buffer: String::new(),
            pending_reason: String::new(),
            input_feedback: String::new(),
            retry_available: false,
            last_required_confirmation: String::new(),
            last_confirmation_input_length: 0,
            last_confirmation_matched: false,
            sanitized_reason_preview: String::new(),
            reason_sanitized_changed: false,
            ctrl_u_clear_used: false,
            esc_cancel_used: false,
            backspace_used: false,
            enter_submit_used: false,
            paste_friendly_input_observed: false,
            last_action: InteractiveLastAction::idle(),
            history: Vec::new(),
            exact_confirmation_mismatch_rejected: false,
            reason_required_enforced: false,
            sanitized_reason_enforced: true,
            candidate_actions_dispatchable: false,
            single_step_actions_dispatchable: false,
            manual_gate_written: false,
        }
    }
}

impl InteractiveLastAction {
    pub fn idle() -> Self {
        Self {
            action: "none".to_string(),
            status: "idle".to_string(),
            result: "awaiting_operator_action".to_string(),
            confirmation_required: false,
            confirmation_matched: false,
            reason_required: false,
            reason_provided: false,
            reason_sanitized: false,
            sanitized_reason: String::new(),
            artifact_paths: Vec::new(),
            blockers: Vec::new(),
            warnings: Vec::new(),
            token_printed: false,
        }
    }

    fn allowed(action: Action, result: &str, artifact_paths: Vec<String>) -> Self {
        Self {
            action: action.action_id().to_string(),
            status: "performed".to_string(),
            result: result.to_string(),
            confirmation_required: confirmation_for(action).is_some(),
            confirmation_matched: confirmation_for(action).is_some(),
            reason_required: reason_required(action),
            reason_provided: false,
            reason_sanitized: false,
            sanitized_reason: String::new(),
            artifact_paths,
            blockers: Vec::new(),
            warnings: Vec::new(),
            token_printed: false,
        }
    }

    fn blocked(action: Action, result: &str, blockers: Vec<String>) -> Self {
        Self {
            action: action.action_id().to_string(),
            status: "blocked".to_string(),
            result: result.to_string(),
            confirmation_required: confirmation_for(action).is_some(),
            confirmation_matched: false,
            reason_required: reason_required(action),
            reason_provided: false,
            reason_sanitized: false,
            sanitized_reason: String::new(),
            artifact_paths: Vec::new(),
            blockers,
            warnings: Vec::new(),
            token_printed: false,
        }
    }
}

impl InteractiveState {
    fn record(&mut self, action: InteractiveLastAction) {
        self.last_action = action.clone();
        self.history.push(action);
        if self.history.len() > 20 {
            self.history.remove(0);
        }
    }

    fn begin_confirmation(&mut self, action: Action, reason: String) {
        self.input_mode = "confirmation".to_string();
        self.pending_action = action.action_id().to_string();
        self.input_buffer.clear();
        self.pending_reason = reason;
        self.input_feedback = "type_or_paste_exact_confirmation".to_string();
        self.retry_available = true;
        self.last_required_confirmation = confirmation_for(action).unwrap_or("").to_string();
        self.last_confirmation_input_length = 0;
        self.last_confirmation_matched = false;
    }

    fn begin_reason(&mut self, action: Action) {
        self.input_mode = "reason".to_string();
        self.pending_action = action.action_id().to_string();
        self.input_buffer.clear();
        self.pending_reason.clear();
        self.input_feedback = "enter_non_empty_sanitized_reason".to_string();
        self.retry_available = true;
        self.sanitized_reason_preview.clear();
        self.reason_sanitized_changed = false;
    }

    fn clear_input(&mut self) {
        self.input_mode = "normal".to_string();
        self.pending_action.clear();
        self.input_buffer.clear();
        self.pending_reason.clear();
        self.retry_available = false;
    }
}

pub fn handle_key_event(
    app: &mut App,
    key: KeyEvent,
    output_dir: &Path,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<InteractiveControl> {
    handle_key_with_modifiers(app, key.code, key.modifiers, output_dir, runtime)
}

fn handle_key_with_modifiers(
    app: &mut App,
    key: KeyCode,
    modifiers: KeyModifiers,
    output_dir: &Path,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<InteractiveControl> {
    match app.interactive.input_mode.as_str() {
        "confirmation" => handle_confirmation_key(app, key, modifiers, output_dir, runtime),
        "reason" => handle_reason_key(app, key, modifiers, output_dir),
        _ => handle_normal_key(app, key, output_dir, runtime),
    }
}

pub fn run_simulation(
    app: &mut App,
    scenario: InteractiveScenario,
    output_dir: &Path,
) -> anyhow::Result<()> {
    match scenario {
        InteractiveScenario::None => {}
        InteractiveScenario::Actions => {
            dispatch_action_sync(app, Action::Refresh, output_dir, "", "")?;
            dispatch_action_sync(app, Action::CopySafeSummary, output_dir, "", "")?;
        }
        InteractiveScenario::ConfirmationReject => {
            dispatch_action_sync(app, Action::GenerateCandidateFixture, output_dir, "", "")?;
            dispatch_action_sync(app, Action::ValidateCandidate, output_dir, "", "")?;
            dispatch_action_sync(app, Action::ReviewCandidate, output_dir, "NO_MATCH", "")?;
        }
        InteractiveScenario::ReasonRequired => {
            dispatch_action_sync(app, Action::SafePause, output_dir, PAUSE_CONFIRMATION, "")?;
        }
        InteractiveScenario::CandidateDispatch => {
            run_candidate_sequence(app, output_dir)?;
        }
        InteractiveScenario::SingleStepDispatch => {
            run_candidate_sequence(app, output_dir)?;
            run_single_step_sequence(app, output_dir)?;
        }
        InteractiveScenario::NoRealExecution => {
            dispatch_action_sync(app, Action::ReviewCandidate, output_dir, "NO_MATCH", "")?;
            dispatch_action_sync(app, Action::SafePause, output_dir, PAUSE_CONFIRMATION, "")?;
            run_candidate_sequence(app, output_dir)?;
            run_single_step_sequence(app, output_dir)?;
        }
    }
    write_interactive_artifacts(output_dir, app)
}

pub fn write_interactive_artifacts(output_dir: &Path, app: &mut App) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;
    app.interactive.manual_gate_written = true;

    let state_json = serde_json::to_string_pretty(&app.interactive)?;
    let report = interactive_report(app, output_dir);
    let report_json = serde_json::to_string_pretty(&report)?;
    let report_md = render_interactive_report_markdown(&report);
    let last_action_json = serde_json::to_string_pretty(&app.interactive.last_action)?;

    write_text(
        &output_dir.join("interactive-state.json"),
        &format!("{state_json}\n"),
    )?;
    write_text(
        &output_dir.join("interactive-report.json"),
        &format!("{report_json}\n"),
    )?;
    write_text(&output_dir.join("interactive-report.md"), &report_md)?;
    write_text(
        &output_dir.join("last-action.json"),
        &format!("{last_action_json}\n"),
    )?;
    write_text(&output_dir.join("manual-gate.md"), &manual_gate_markdown())?;
    Ok(())
}

pub fn interactive_report(app: &App, output_dir: &Path) -> InteractiveReport {
    let blockers = Vec::new();
    let mut warnings = vec![
        "fixture_safe_interactive_action_runner_only".to_string(),
        "mg369_manual_docs_only_experiment_not_performed_by_mg368e".to_string(),
    ];
    if app.interactive.exact_confirmation_mismatch_rejected {
        warnings.push("exact_confirmation_mismatch_rejected".to_string());
    }
    if app.interactive.reason_required_enforced {
        warnings.push("reason_required_enforced".to_string());
    }
    if app.interactive.last_action.status == "blocked" {
        warnings.push(format!(
            "last_action_blocked:{}",
            app.interactive.last_action.result
        ));
    }

    InteractiveReport {
        schema: INTERACTIVE_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "interactive-unblocker",
        interactive_loop_available: true,
        keyboard_actions_registered: keyboard_actions_registered(),
        keyboard_actions: Action::all()
            .into_iter()
            .map(|action| action.key())
            .collect(),
        confirmation_input_available: true,
        reason_input_available: true,
        candidate_actions_dispatchable: app.interactive.candidate_actions_dispatchable,
        single_step_actions_dispatchable: app.interactive.single_step_actions_dispatchable,
        exact_confirmations_required: exact_confirmations(),
        exact_confirmation_mismatch_rejected: app.interactive.exact_confirmation_mismatch_rejected,
        reason_required_enforced: app.interactive.reason_required_enforced,
        sanitized_reason_enforced: app.interactive.sanitized_reason_enforced,
        manual_gate_written: app.interactive.manual_gate_written,
        last_action: app.interactive.last_action.clone(),
        action_history: app.interactive.history.clone(),
        active_actions: Action::all().into_iter().map(Action::status).collect(),
        panels_rendered: PANELS.to_vec(),
        artifact_paths: interactive_artifact_paths(output_dir),
        real_task_execution_enabled: false,
        real_branch_creation_enabled: false,
        real_pr_creation_enabled: false,
        queue_runner_started: false,
        worker_loop_started: false,
        run_forever_started: false,
        hermes_live_called: false,
        mcp_run_called: false,
        auto_merge_enabled: false,
        release_created: false,
        tag_created: false,
        asset_uploaded: false,
        token_printed: false,
        blockers,
        warnings,
    }
}

fn handle_normal_key(
    app: &mut App,
    key: KeyCode,
    output_dir: &Path,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<InteractiveControl> {
    match key {
        KeyCode::Char('q') | KeyCode::Esc => Ok(InteractiveControl::Quit),
        KeyCode::Tab | KeyCode::Char(']') => {
            app.view_model.next_tab();
            Ok(InteractiveControl::Continue)
        }
        KeyCode::BackTab | KeyCode::Char('[') => {
            app.view_model.previous_tab();
            Ok(InteractiveControl::Continue)
        }
        KeyCode::Char('?') => {
            app.view_model.toggle_help();
            Ok(InteractiveControl::Continue)
        }
        KeyCode::Up => {
            if app.interactive.selected_action_index == 0 {
                app.interactive.selected_action_index = Action::all().len() - 1;
            } else {
                app.interactive.selected_action_index -= 1;
            }
            Ok(InteractiveControl::Continue)
        }
        KeyCode::Down => {
            app.interactive.selected_action_index =
                (app.interactive.selected_action_index + 1) % Action::all().len();
            Ok(InteractiveControl::Continue)
        }
        KeyCode::Enter => {
            let actions = Action::all();
            let action = actions
                .get(app.interactive.selected_action_index)
                .copied()
                .unwrap_or(Action::Refresh);
            begin_or_dispatch(app, action, output_dir, runtime)
        }
        KeyCode::Char(value) => {
            if let Some(action) = Action::from_key(value) {
                begin_or_dispatch(app, action, output_dir, runtime)
            } else {
                Ok(InteractiveControl::Continue)
            }
        }
        _ => Ok(InteractiveControl::Continue),
    }
}

fn handle_confirmation_key(
    app: &mut App,
    key: KeyCode,
    modifiers: KeyModifiers,
    output_dir: &Path,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<InteractiveControl> {
    if modifiers.contains(KeyModifiers::CONTROL) && matches!(key, KeyCode::Char('u' | 'U')) {
        app.interactive.ctrl_u_clear_used = true;
        app.interactive.input_buffer.clear();
        app.interactive.input_feedback = "confirmation_input_cleared".to_string();
        update_confirmation_metrics(app);
        app.sync_view_model();
        write_interactive_artifacts(output_dir, app)?;
        return Ok(InteractiveControl::Continue);
    }

    match key {
        KeyCode::Esc => {
            let action = pending_action(app).unwrap_or(Action::Refresh);
            app.interactive.esc_cancel_used = true;
            app.interactive.record(InteractiveLastAction::blocked(
                action,
                "confirmation_cancelled",
                vec!["confirmation_cancelled".to_string()],
            ));
            app.interactive.clear_input();
            write_interactive_artifacts(output_dir, app)?;
        }
        KeyCode::Enter => {
            let action = pending_action(app).unwrap_or(Action::Refresh);
            let confirmation = app.interactive.input_buffer.clone();
            let reason = app.interactive.pending_reason.clone();
            app.interactive.enter_submit_used = true;
            update_confirmation_metrics(app);
            app.interactive.clear_input();
            dispatch_action_async(app, action, output_dir, &confirmation, &reason, runtime)?;
        }
        KeyCode::Backspace => {
            app.interactive.backspace_used = true;
            app.interactive.input_buffer.pop();
            update_confirmation_metrics(app);
        }
        KeyCode::Char(value) => {
            app.interactive.paste_friendly_input_observed = true;
            app.interactive.input_buffer.push(value);
            update_confirmation_metrics(app);
        }
        _ => {}
    }
    app.sync_view_model();
    Ok(InteractiveControl::Continue)
}

fn handle_reason_key(
    app: &mut App,
    key: KeyCode,
    modifiers: KeyModifiers,
    output_dir: &Path,
) -> anyhow::Result<InteractiveControl> {
    if modifiers.contains(KeyModifiers::CONTROL) && matches!(key, KeyCode::Char('u' | 'U')) {
        app.interactive.ctrl_u_clear_used = true;
        app.interactive.input_buffer.clear();
        app.interactive.input_feedback = "reason_input_cleared".to_string();
        update_reason_preview(app);
        app.sync_view_model();
        write_interactive_artifacts(output_dir, app)?;
        return Ok(InteractiveControl::Continue);
    }

    match key {
        KeyCode::Esc => {
            let action = pending_action(app).unwrap_or(Action::Refresh);
            app.interactive.esc_cancel_used = true;
            app.interactive.record(InteractiveLastAction::blocked(
                action,
                "reason_cancelled",
                vec!["reason_cancelled".to_string()],
            ));
            app.interactive.clear_input();
            write_interactive_artifacts(output_dir, app)?;
        }
        KeyCode::Enter => {
            let action = pending_action(app).unwrap_or(Action::Refresh);
            let reason = sanitize_reason(&app.interactive.input_buffer);
            app.interactive.enter_submit_used = true;
            app.interactive.sanitized_reason_preview = reason.clone();
            app.interactive.reason_sanitized_changed = !app.interactive.input_buffer.is_empty()
                && reason != app.interactive.input_buffer.trim();
            if reason.is_empty() {
                app.interactive.reason_required_enforced = true;
                app.interactive.input_feedback = "reason_required".to_string();
                app.interactive.record(InteractiveLastAction::blocked(
                    action,
                    "reason_required",
                    vec!["reason_required".to_string()],
                ));
                app.interactive.clear_input();
                write_interactive_artifacts(output_dir, app)?;
            } else {
                app.interactive.begin_confirmation(action, reason);
            }
        }
        KeyCode::Backspace => {
            app.interactive.backspace_used = true;
            app.interactive.input_buffer.pop();
            update_reason_preview(app);
        }
        KeyCode::Char(value) => {
            app.interactive.paste_friendly_input_observed = true;
            app.interactive.input_buffer.push(value);
            update_reason_preview(app);
        }
        _ => {}
    }
    app.sync_view_model();
    Ok(InteractiveControl::Continue)
}

fn begin_or_dispatch(
    app: &mut App,
    action: Action,
    output_dir: &Path,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<InteractiveControl> {
    if action == Action::Quit {
        return Ok(InteractiveControl::Quit);
    }
    if reason_required(action) {
        app.interactive.begin_reason(action);
        write_interactive_artifacts(output_dir, app)?;
        return Ok(InteractiveControl::Continue);
    }
    if confirmation_for(action).is_some() {
        app.interactive.begin_confirmation(action, String::new());
        write_interactive_artifacts(output_dir, app)?;
        return Ok(InteractiveControl::Continue);
    }
    dispatch_action_async(app, action, output_dir, "", "", runtime)?;
    Ok(InteractiveControl::Continue)
}

fn dispatch_action_async(
    app: &mut App,
    action: Action,
    output_dir: &Path,
    confirmation: &str,
    reason: &str,
    runtime: &mut OperatorRuntime,
) -> anyhow::Result<()> {
    if let Some(expected) = confirmation_for(action) {
        if confirmation != expected {
            app.interactive.exact_confirmation_mismatch_rejected = true;
            app.interactive.input_feedback = "exact_confirmation_mismatch".to_string();
            app.interactive.retry_available = true;
            app.interactive.last_required_confirmation = expected.to_string();
            app.interactive.last_confirmation_input_length = confirmation.chars().count();
            app.interactive.last_confirmation_matched = false;
            app.interactive.record(InteractiveLastAction::blocked(
                action,
                "exact_confirmation_mismatch",
                vec!["exact_confirmation_mismatch".to_string()],
            ));
            app.sync_view_model();
            write_interactive_artifacts(output_dir, app)?;
            return Ok(());
        }
    }

    let sanitized_reason = sanitize_reason(reason);
    let reason_sanitized = !reason.is_empty() && sanitized_reason != reason.trim();
    if reason_required(action) && sanitized_reason.is_empty() {
        app.interactive.reason_required_enforced = true;
        app.interactive.record(InteractiveLastAction::blocked(
            action,
            "reason_required",
            vec!["reason_required".to_string()],
        ));
        app.sync_view_model();
        write_interactive_artifacts(output_dir, app)?;
        return Ok(());
    }

    let Some(command) = OperatorCommand::from_action(action) else {
        return Ok(());
    };
    let options = RuntimeDispatchOptions::new(output_dir.to_path_buf(), app.state_mode)
        .with_reason(sanitized_reason.clone());
    match runtime.enqueue(command, options) {
        EnqueueOutcome::Started {
            command_id,
            command,
        } => {
            app.view_model.command_started(command_id, command.label());
            let mut last =
                InteractiveLastAction::allowed(action, "command_enqueued_nonblocking", Vec::new());
            last.status = CommandStatus::Queued.as_str().to_string();
            last.reason_required = reason_required(action);
            last.reason_provided = !sanitized_reason.is_empty();
            last.reason_sanitized = reason_sanitized;
            last.sanitized_reason = sanitized_reason;
            app.interactive.record(last);
        }
        EnqueueOutcome::Blocked(result) => {
            app.view_model.apply_command_result(result.clone());
            app.interactive.record(InteractiveLastAction::blocked(
                action,
                &result.result_summary,
                result.blockers,
            ));
        }
    }

    if reason_sanitized {
        app.interactive.sanitized_reason_enforced = true;
    }
    app.sync_view_model();
    write_interactive_artifacts(output_dir, app)
}

pub fn record_command_result(
    app: &mut App,
    result: &OperatorCommandResult,
    output_dir: &Path,
) -> anyhow::Result<()> {
    let action = action_for_command(result.command);
    if matches!(
        result.command,
        OperatorCommand::GenerateCandidateFixture
            | OperatorCommand::ValidateCandidate
            | OperatorCommand::ReviewCandidate
            | OperatorCommand::AppendCandidate
    ) {
        app.interactive.candidate_actions_dispatchable = true;
    }
    if matches!(
        result.command,
        OperatorCommand::PreviewBoundedAction
            | OperatorCommand::StartOneFixture
            | OperatorCommand::SafePauseFixture
            | OperatorCommand::AbortPreview
    ) {
        app.interactive.single_step_actions_dispatchable = true;
    }

    let last = InteractiveLastAction {
        action: action.action_id().to_string(),
        status: result.status.as_str().to_string(),
        result: result.result_summary.clone(),
        confirmation_required: confirmation_for(action).is_some(),
        confirmation_matched: confirmation_for(action).is_some(),
        reason_required: reason_required(action),
        reason_provided: false,
        reason_sanitized: false,
        sanitized_reason: String::new(),
        artifact_paths: result.artifact_paths.clone(),
        blockers: result.blockers.clone(),
        warnings: result.warnings.clone(),
        token_printed: false,
    };
    app.interactive.record(last);
    app.sync_view_model();
    write_interactive_artifacts(output_dir, app)
}

fn action_for_command(command: OperatorCommand) -> Action {
    match command {
        OperatorCommand::RefreshLocalCloud => Action::Refresh,
        OperatorCommand::GenerateCandidateFixture => Action::GenerateCandidateFixture,
        OperatorCommand::ValidateCandidate => Action::ValidateCandidate,
        OperatorCommand::ReviewCandidate => Action::ReviewCandidate,
        OperatorCommand::AppendCandidate => Action::AppendCandidate,
        OperatorCommand::PreviewBoundedAction => Action::PreviewBoundedAction,
        OperatorCommand::StartOneFixture => Action::StartOneGoal,
        OperatorCommand::SafePauseFixture => Action::SafePause,
        OperatorCommand::AbortPreview => Action::AbortTerminate,
        OperatorCommand::CopySafeSummary => Action::CopySafeSummary,
    }
}

fn dispatch_action_sync(
    app: &mut App,
    action: Action,
    output_dir: &Path,
    confirmation: &str,
    reason: &str,
) -> anyhow::Result<()> {
    if let Some(expected) = confirmation_for(action) {
        if confirmation != expected {
            app.interactive.exact_confirmation_mismatch_rejected = true;
            app.interactive.input_feedback = "exact_confirmation_mismatch".to_string();
            app.interactive.retry_available = true;
            app.interactive.last_required_confirmation = expected.to_string();
            app.interactive.last_confirmation_input_length = confirmation.chars().count();
            app.interactive.last_confirmation_matched = false;
            app.interactive.record(InteractiveLastAction::blocked(
                action,
                "exact_confirmation_mismatch",
                vec!["exact_confirmation_mismatch".to_string()],
            ));
            write_interactive_artifacts(output_dir, app)?;
            return Ok(());
        }
    }

    let sanitized_reason = sanitize_reason(reason);
    let reason_sanitized = !reason.is_empty() && sanitized_reason != reason.trim();
    if reason_required(action) && sanitized_reason.is_empty() {
        app.interactive.reason_required_enforced = true;
        app.interactive.record(InteractiveLastAction::blocked(
            action,
            "reason_required",
            vec!["reason_required".to_string()],
        ));
        write_interactive_artifacts(output_dir, app)?;
        return Ok(());
    }

    let artifact_paths = match action {
        Action::Refresh => {
            app.state_mode = StateMode::LocalCloud;
            app.refresh_state(output_dir);
            app.write_snapshot_artifacts(output_dir)?;
            interactive_artifact_paths(output_dir)
        }
        Action::CopySafeSummary => {
            app.write_snapshot_artifacts(output_dir)?;
            interactive_artifact_paths(output_dir)
        }
        Action::GenerateCandidateFixture => {
            run_candidate_action(app, output_dir, CandidateAction::Generate, "", "")?;
            app.interactive.candidate_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::ValidateCandidate => {
            run_candidate_action(app, output_dir, CandidateAction::Validate, "", "")?;
            app.interactive.candidate_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::ReviewCandidate => {
            run_candidate_action(
                app,
                output_dir,
                CandidateAction::ReviewApprove,
                REVIEW_CONFIRMATION,
                "",
            )?;
            app.interactive.candidate_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::AppendCandidate => {
            run_candidate_action(app, output_dir, CandidateAction::AppendPreview, "", "")?;
            run_candidate_action(
                app,
                output_dir,
                CandidateAction::AppendApplyFixture,
                "",
                APPEND_CONFIRMATION,
            )?;
            app.interactive.candidate_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::PreviewBoundedAction => {
            run_single_step_action(
                app,
                output_dir,
                SingleStepAction::PreviewBoundedAction,
                "",
                "",
                "",
                "",
                "",
            )?;
            app.interactive.single_step_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::StartOneGoal => {
            run_single_step_action(
                app,
                output_dir,
                SingleStepAction::StartOneFixture,
                START_CONFIRMATION,
                "",
                "",
                "",
                "",
            )?;
            app.interactive.single_step_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::SafePause => {
            run_single_step_action(
                app,
                output_dir,
                SingleStepAction::SafePause,
                "",
                PAUSE_CONFIRMATION,
                "",
                &sanitized_reason,
                "",
            )?;
            app.interactive.single_step_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::AbortTerminate => {
            run_single_step_action(
                app,
                output_dir,
                SingleStepAction::AbortPreview,
                "",
                "",
                ABORT_CONFIRMATION,
                "",
                &sanitized_reason,
            )?;
            app.interactive.single_step_actions_dispatchable = true;
            interactive_artifact_paths(output_dir)
        }
        Action::Quit => interactive_artifact_paths(output_dir),
    };

    let mut last =
        InteractiveLastAction::allowed(action, "action_dispatched_fixture_safe", artifact_paths);
    last.reason_required = reason_required(action);
    last.reason_provided = !sanitized_reason.is_empty();
    last.reason_sanitized = reason_sanitized;
    last.sanitized_reason = sanitized_reason;
    if reason_sanitized {
        app.interactive.sanitized_reason_enforced = true;
    }
    app.interactive.record(last);
    write_interactive_artifacts(output_dir, app)
}

fn run_candidate_sequence(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    dispatch_action_sync(app, Action::GenerateCandidateFixture, output_dir, "", "")?;
    dispatch_action_sync(app, Action::ValidateCandidate, output_dir, "", "")?;
    dispatch_action_sync(
        app,
        Action::ReviewCandidate,
        output_dir,
        REVIEW_CONFIRMATION,
        "",
    )?;
    dispatch_action_sync(
        app,
        Action::AppendCandidate,
        output_dir,
        APPEND_CONFIRMATION,
        "",
    )?;
    Ok(())
}

fn run_single_step_sequence(app: &mut App, output_dir: &Path) -> anyhow::Result<()> {
    dispatch_action_sync(app, Action::PreviewBoundedAction, output_dir, "", "")?;
    dispatch_action_sync(
        app,
        Action::StartOneGoal,
        output_dir,
        START_CONFIRMATION,
        "",
    )?;
    dispatch_action_sync(
        app,
        Action::SafePause,
        output_dir,
        PAUSE_CONFIRMATION,
        "fixture safe pause",
    )?;
    dispatch_action_sync(
        app,
        Action::AbortTerminate,
        output_dir,
        ABORT_CONFIRMATION,
        "MG368E abort preview only",
    )?;
    Ok(())
}

fn run_candidate_action(
    app: &mut App,
    output_dir: &Path,
    action: CandidateAction,
    review_confirm: &str,
    append_confirm: &str,
) -> anyhow::Result<()> {
    app.state_mode = StateMode::CandidateFlow;
    app.refresh_state(output_dir);
    let mut cli = Cli::default();
    cli.state_mode = StateMode::CandidateFlow;
    cli.output_dir = output_dir.to_path_buf();
    cli.output_dir_provided = true;
    cli.candidate_action = action;
    cli.review_confirm = review_confirm.to_string();
    cli.append_confirm = append_confirm.to_string();
    app.run_candidate_action(&cli);
    app.write_snapshot_artifacts(output_dir)
}

fn run_single_step_action(
    app: &mut App,
    output_dir: &Path,
    action: SingleStepAction,
    start_confirm: &str,
    pause_confirm: &str,
    abort_confirm: &str,
    pause_reason: &str,
    abort_reason: &str,
) -> anyhow::Result<()> {
    app.state_mode = StateMode::SingleStep;
    app.refresh_state(output_dir);
    let mut cli = Cli::default();
    cli.state_mode = StateMode::SingleStep;
    cli.output_dir = output_dir.to_path_buf();
    cli.output_dir_provided = true;
    cli.single_step_action = action;
    cli.single_step_mode = "fixture".to_string();
    cli.start_confirm = start_confirm.to_string();
    cli.pause_confirm = pause_confirm.to_string();
    cli.abort_confirm = abort_confirm.to_string();
    cli.pause_reason = pause_reason.to_string();
    cli.abort_reason = abort_reason.to_string();
    app.run_single_step_action(&cli);
    app.write_snapshot_artifacts(output_dir)
}

fn pending_action(app: &App) -> Option<Action> {
    Action::from_action_id(&app.interactive.pending_action)
}

pub(crate) fn confirmation_for(action: Action) -> Option<&'static str> {
    match action {
        Action::ReviewCandidate => Some(REVIEW_CONFIRMATION),
        Action::AppendCandidate => Some(APPEND_CONFIRMATION),
        Action::StartOneGoal => Some(START_CONFIRMATION),
        Action::SafePause => Some(PAUSE_CONFIRMATION),
        Action::AbortTerminate => Some(ABORT_CONFIRMATION),
        _ => None,
    }
}

pub(crate) fn reason_required(action: Action) -> bool {
    matches!(action, Action::SafePause | Action::AbortTerminate)
}

pub(crate) fn exact_confirmations() -> Vec<&'static str> {
    vec![
        REVIEW_CONFIRMATION,
        APPEND_CONFIRMATION,
        START_CONFIRMATION,
        PAUSE_CONFIRMATION,
        ABORT_CONFIRMATION,
    ]
}

fn keyboard_actions_registered() -> bool {
    let required = ["r", "g", "v", "e", "a", "p", "s", "h", "x", "c", "q"];
    required
        .iter()
        .all(|key| Action::all().iter().any(|action| action.key() == *key))
}

pub(crate) fn sanitize_reason(value: &str) -> String {
    let mut safe = value.trim().replace(['\r', '\n', '\t'], " ");
    for marker in ["Authorization", "Bearer", "token=", "secret=", "password="] {
        if safe
            .to_ascii_lowercase()
            .contains(&marker.to_ascii_lowercase())
        {
            safe = "redacted_reason".to_string();
            break;
        }
    }
    if safe.len() > 180 {
        safe.truncate(180);
    }
    safe
}

fn update_confirmation_metrics(app: &mut App) {
    let action = pending_action(app).unwrap_or(Action::Refresh);
    let expected = confirmation_for(action).unwrap_or("");
    app.interactive.last_required_confirmation = expected.to_string();
    app.interactive.last_confirmation_input_length = app.interactive.input_buffer.chars().count();
    app.interactive.last_confirmation_matched =
        !expected.is_empty() && app.interactive.input_buffer == expected;
    app.interactive.input_feedback = if app.interactive.last_confirmation_matched {
        "exact_confirmation_matches".to_string()
    } else {
        "waiting_for_exact_confirmation".to_string()
    };
}

fn update_reason_preview(app: &mut App) {
    let preview = sanitize_reason(&app.interactive.input_buffer);
    app.interactive.reason_sanitized_changed =
        !app.interactive.input_buffer.is_empty() && preview != app.interactive.input_buffer.trim();
    app.interactive.sanitized_reason_preview = preview;
    app.interactive.input_feedback = if app.interactive.sanitized_reason_preview.is_empty() {
        "reason_required".to_string()
    } else if app.interactive.reason_sanitized_changed {
        "sanitized_reason_preview_changed".to_string()
    } else {
        "reason_preview_ready".to_string()
    };
}

fn interactive_artifact_paths(output_dir: &Path) -> Vec<String> {
    [
        "interactive-state.json",
        "interactive-report.json",
        "interactive-report.md",
        "last-action.json",
        "manual-gate.md",
        "operator-tui-candidate-state.json",
        "operator-tui-candidate-report.json",
        "operator-tui-single-step-state.json",
        "operator-tui-single-step-report.json",
    ]
    .iter()
    .map(|name| path_for_report(&output_dir.join(name)))
    .collect()
}

fn render_interactive_report_markdown(report: &InteractiveReport) -> String {
    format!(
        "# Operator TUI MG368E Interactive Unblocker Report\n\n- schema: {}\n- mode: {}\n- interactive_loop_available: {}\n- keyboard_actions_registered: {}\n- confirmation_input_available: {}\n- reason_input_available: {}\n- candidate_actions_dispatchable: {}\n- single_step_actions_dispatchable: {}\n- exact_confirmation_mismatch_rejected: {}\n- reason_required_enforced: {}\n- sanitized_reason_enforced: {}\n- manual_gate_written: {}\n- last_action: {} {}\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- queue_runner_started: false\n- worker_loop_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Manual Gate\n\n{}\n",
        report.schema,
        report.mode,
        report.interactive_loop_available,
        report.keyboard_actions_registered,
        report.confirmation_input_available,
        report.reason_input_available,
        report.candidate_actions_dispatchable,
        report.single_step_actions_dispatchable,
        report.exact_confirmation_mismatch_rejected,
        report.reason_required_enforced,
        report.sanitized_reason_enforced,
        report.manual_gate_written,
        report.last_action.action,
        report.last_action.result,
        MG369_MANUAL_GATE_MESSAGE
    )
}

fn manual_gate_markdown() -> String {
    format!(
        "# MG369 Manual Gate\n\n{}\n\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- queue_runner_started: false\n- worker_loop_started: false\n- run_forever_started: false\n- token_printed: false\n",
        MG369_MANUAL_GATE_MESSAGE
    )
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    let path = PathBuf::from(path);
    path.to_string_lossy().replace('\\', "/")
}

fn now_utc() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}
