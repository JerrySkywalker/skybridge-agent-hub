use serde::Serialize;

use crate::{
    actions::Action,
    candidate::{APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    commands::{CommandStatus, OperatorCommandResult},
    interactive::InteractiveState,
    model::OperatorState,
    single_step::{ABORT_CONFIRMATION, PAUSE_CONFIRMATION, START_CONFIRMATION},
    ui_layout::OperatorTab,
};

#[derive(Debug, Clone, Serialize)]
pub struct ViewModel {
    pub current_operator_state: OperatorState,
    pub selected_action: String,
    pub selected_action_index: usize,
    pub input_mode: String,
    pub pending_action: String,
    pub pending_action_label: String,
    pub pending_risk_class: String,
    pub pending_confirmation: String,
    pub pending_reason: String,
    pub input_buffer: String,
    pub input_length: usize,
    pub input_matches_confirmation: bool,
    pub input_feedback: String,
    pub retry_or_cancel_available: bool,
    pub confirmation_expected_length: usize,
    pub confirmation_actual_length: usize,
    pub confirmation_first_mismatch_index: Option<usize>,
    pub confirmation_has_leading_or_trailing_whitespace: bool,
    pub confirmation_contains_cr_lf_tab: bool,
    pub confirmation_contains_non_ascii: bool,
    pub confirmation_looks_truncated: bool,
    pub confirmation_likely_duplicate_paste: bool,
    pub confirmation_retry_guidance: String,
    pub confirmation_normalized: bool,
    pub confirmation_normalization_reason: String,
    pub confirmation_raw_input_persisted: bool,
    pub sanitized_reason_preview: String,
    pub reason_sanitized_changed: bool,
    pub active_command_id: Option<u64>,
    pub active_command_label: String,
    pub active_command_elapsed_seconds: u64,
    pub running_wait_guidance: String,
    pub running_guard_visible: bool,
    pub mutation_actions_blocked_while_running: bool,
    pub command_already_running_feedback_visible: bool,
    pub command_status: CommandStatus,
    pub last_command_result: Option<OperatorCommandResult>,
    pub artifact_paths: Vec<String>,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
    pub safety_flags: ViewModelSafetyFlags,
    pub ui_loop_nonblocking: bool,
    pub running_state_rendered: bool,
    pub active_tab: OperatorTab,
    pub help_visible: bool,
    pub manual_dry_run_guide_visible: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ViewModelSafetyFlags {
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

impl ViewModel {
    pub fn new(state: OperatorState) -> Self {
        let blockers = state.campaign.blockers.clone();
        let warnings = state.campaign.warnings.clone();
        Self {
            current_operator_state: state,
            selected_action: Action::Refresh.action_id().to_string(),
            selected_action_index: 0,
            input_mode: "normal".to_string(),
            pending_action: String::new(),
            pending_action_label: String::new(),
            pending_risk_class: String::new(),
            pending_confirmation: String::new(),
            pending_reason: String::new(),
            input_buffer: String::new(),
            input_length: 0,
            input_matches_confirmation: false,
            input_feedback: String::new(),
            retry_or_cancel_available: false,
            confirmation_expected_length: 0,
            confirmation_actual_length: 0,
            confirmation_first_mismatch_index: None,
            confirmation_has_leading_or_trailing_whitespace: false,
            confirmation_contains_cr_lf_tab: false,
            confirmation_contains_non_ascii: false,
            confirmation_looks_truncated: false,
            confirmation_likely_duplicate_paste: false,
            confirmation_retry_guidance: String::new(),
            confirmation_normalized: false,
            confirmation_normalization_reason: "none".to_string(),
            confirmation_raw_input_persisted: false,
            sanitized_reason_preview: String::new(),
            reason_sanitized_changed: false,
            active_command_id: None,
            active_command_label: String::new(),
            active_command_elapsed_seconds: 0,
            running_wait_guidance: "wait for completed/blocked/timed_out before continuing"
                .to_string(),
            running_guard_visible: false,
            mutation_actions_blocked_while_running: false,
            command_already_running_feedback_visible: false,
            command_status: CommandStatus::Idle,
            last_command_result: None,
            artifact_paths: Vec::new(),
            blockers,
            warnings,
            safety_flags: ViewModelSafetyFlags::disabled(),
            ui_loop_nonblocking: true,
            running_state_rendered: false,
            active_tab: OperatorTab::Overview,
            help_visible: false,
            manual_dry_run_guide_visible: false,
        }
    }

    pub fn sync_state(&mut self, state: &OperatorState) {
        self.current_operator_state = state.clone();
        self.safety_flags = ViewModelSafetyFlags::from_state(state);
        self.blockers = state.campaign.blockers.clone();
        self.warnings = state.campaign.warnings.clone();
        if let Some(result) = &self.last_command_result {
            self.artifact_paths = result.artifact_paths.clone();
            self.blockers.extend(result.blockers.clone());
            self.warnings.extend(result.warnings.clone());
        }
    }

    pub fn sync_interactive(&mut self, interactive: &InteractiveState) {
        self.selected_action_index = interactive.selected_action_index;
        self.selected_action = Action::all()
            .get(interactive.selected_action_index)
            .map(|action| action.action_id().to_string())
            .unwrap_or_else(|| Action::Refresh.action_id().to_string());
        self.input_mode = interactive.input_mode.to_string();
        self.pending_action = interactive.pending_action.to_string();
        let action = Action::from_action_id(&interactive.pending_action);
        self.pending_action_label = action
            .map(|action| action.label().to_string())
            .unwrap_or_else(|| "none".to_string());
        self.pending_risk_class = action
            .map(risk_class_for_action)
            .unwrap_or_else(|| "no real execution".to_string());
        self.pending_confirmation = action
            .and_then(confirmation_for_action)
            .unwrap_or("")
            .to_string();
        self.pending_reason = interactive.pending_reason.to_string();
        self.input_buffer = interactive.input_buffer.to_string();
        self.input_length = interactive.input_buffer.chars().count();
        self.input_matches_confirmation = !self.pending_confirmation.is_empty()
            && interactive.input_buffer == self.pending_confirmation;
        self.input_feedback = interactive.input_feedback.to_string();
        self.retry_or_cancel_available = interactive.retry_available;
        let diagnostics = &interactive.last_confirmation_diagnostics;
        self.confirmation_expected_length = diagnostics.expected_confirmation_length;
        self.confirmation_actual_length = diagnostics.actual_input_length;
        self.confirmation_first_mismatch_index = diagnostics.first_mismatch_index;
        self.confirmation_has_leading_or_trailing_whitespace =
            diagnostics.has_leading_or_trailing_whitespace;
        self.confirmation_contains_cr_lf_tab = diagnostics.contains_cr_lf_tab;
        self.confirmation_contains_non_ascii = diagnostics.contains_non_ascii;
        self.confirmation_looks_truncated = diagnostics.looks_truncated;
        self.confirmation_likely_duplicate_paste = diagnostics.likely_duplicate_paste;
        self.confirmation_retry_guidance = diagnostics.retry_guidance.clone();
        self.confirmation_normalized = diagnostics.confirmation_normalized;
        self.confirmation_normalization_reason = diagnostics.normalization_reason.clone();
        self.confirmation_raw_input_persisted = diagnostics.raw_input_persisted;
        self.command_already_running_feedback_visible =
            interactive.command_already_running_feedback_visible;
        self.sanitized_reason_preview = sanitize_reason_preview(&interactive.input_buffer);
        if !interactive.pending_reason.is_empty() && self.sanitized_reason_preview.is_empty() {
            self.sanitized_reason_preview = interactive.pending_reason.to_string();
        }
        self.reason_sanitized_changed = interactive.reason_sanitized_changed
            || (!interactive.input_buffer.is_empty()
                && self.sanitized_reason_preview != interactive.input_buffer.trim());
    }

    pub fn command_started(&mut self, command_id: u64, label: impl Into<String>) {
        self.active_command_id = Some(command_id);
        self.active_command_label = label.into();
        self.active_command_elapsed_seconds = 0;
        self.command_status = CommandStatus::Running;
        self.running_state_rendered = true;
        self.running_guard_visible = true;
        self.mutation_actions_blocked_while_running = true;
    }

    pub fn apply_command_result(&mut self, result: OperatorCommandResult) {
        self.command_status = result.status;
        self.active_command_id = None;
        self.active_command_label.clear();
        self.active_command_elapsed_seconds = 0;
        self.running_guard_visible = false;
        self.mutation_actions_blocked_while_running = false;
        self.artifact_paths = result.artifact_paths.clone();
        self.blockers = result.blockers.clone();
        self.warnings = result.warnings.clone();
        self.last_command_result = Some(result);
    }

    pub fn sync_running_guard(
        &mut self,
        active_label: Option<String>,
        elapsed_seconds: Option<u64>,
    ) {
        if let Some(label) = active_label {
            self.active_command_label = label;
            self.active_command_elapsed_seconds = elapsed_seconds.unwrap_or(0);
            self.running_guard_visible = true;
            self.mutation_actions_blocked_while_running = true;
            self.running_state_rendered = true;
            if self.command_status == CommandStatus::Idle {
                self.command_status = CommandStatus::Running;
            }
        }
    }

    pub fn status_lines(&self) -> Vec<String> {
        let active = if let Some(id) = self.active_command_id {
            format!("{}#{}", value_or_none(&self.active_command_label), id)
        } else {
            "none".to_string()
        };
        let last = self
            .last_command_result
            .as_ref()
            .map(|result| format!("{} {}", result.command.label(), result.result_summary))
            .unwrap_or_else(|| "none".to_string());
        vec![
            format!("runtime: UI responsive while command runs"),
            format!("command_status: {}", self.command_status.as_str()),
            format!("running_command: {active}"),
            format!(
                "running_elapsed_seconds: {}",
                self.active_command_elapsed_seconds
            ),
            format!("running_wait_guidance: {}", self.running_wait_guidance),
            format!("running_guard_visible: {}", self.running_guard_visible),
            format!(
                "mutation_actions_blocked_while_running: {}",
                self.mutation_actions_blocked_while_running
            ),
            format!(
                "command_already_running_feedback_visible: {}",
                self.command_already_running_feedback_visible
            ),
            format!("last_command_result: {last}"),
        ]
    }

    pub fn next_tab(&mut self) {
        self.active_tab = self.active_tab.next();
        self.help_visible = false;
    }

    pub fn previous_tab(&mut self) {
        self.active_tab = self.active_tab.previous();
        self.help_visible = false;
    }

    pub fn toggle_help(&mut self) {
        self.help_visible = !self.help_visible;
    }
}

impl ViewModelSafetyFlags {
    pub fn disabled() -> Self {
        Self {
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
            token_printed: false,
        }
    }

    pub fn from_state(state: &OperatorState) -> Self {
        let safety = &state.safety;
        Self {
            real_task_execution_enabled: false,
            real_branch_creation_enabled: false,
            real_pr_creation_enabled: false,
            task_created: safety.task_created,
            task_claimed: safety.task_claimed,
            execution_started: safety.execution_started,
            worker_loop_started: safety.worker_loop_started,
            queue_runner_started: safety.queue_runner_started,
            run_forever_started: false,
            hermes_live_called: safety.hermes_live_called,
            mcp_run_called: safety.mcp_run_called,
            auto_merge_enabled: safety.auto_merge_enabled,
            release_created: safety.release_created,
            tag_created: safety.tag_created,
            asset_uploaded: safety.asset_uploaded,
            token_printed: safety.token_printed,
        }
    }
}

fn confirmation_for_action(action: Action) -> Option<&'static str> {
    match action {
        Action::ReviewCandidate => Some(REVIEW_CONFIRMATION),
        Action::AppendCandidate => Some(APPEND_CONFIRMATION),
        Action::StartOneGoal => Some(START_CONFIRMATION),
        Action::SafePause => Some(PAUSE_CONFIRMATION),
        Action::AbortTerminate => Some(ABORT_CONFIRMATION),
        _ => None,
    }
}

fn risk_class_for_action(action: Action) -> String {
    match action {
        Action::ReviewCandidate | Action::AppendCandidate | Action::StartOneGoal => {
            "fixture-safe | metadata-only | no real execution".to_string()
        }
        Action::SafePause | Action::AbortTerminate => {
            "fixture-safe | metadata-only | no real execution".to_string()
        }
        _ => "no real execution".to_string(),
    }
}

fn sanitize_reason_preview(value: &str) -> String {
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

fn value_or_none(value: &str) -> &str {
    if value.is_empty() {
        "none"
    } else {
        value
    }
}
