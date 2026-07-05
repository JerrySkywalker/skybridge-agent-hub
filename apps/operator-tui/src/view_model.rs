use serde::Serialize;

use crate::{
    actions::Action,
    candidate::{APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    commands::{CommandStatus, OperatorCommandResult},
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
    pub sanitized_reason_preview: String,
    pub reason_sanitized_changed: bool,
    pub active_command_id: Option<u64>,
    pub active_command_label: String,
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
            sanitized_reason_preview: String::new(),
            reason_sanitized_changed: false,
            active_command_id: None,
            active_command_label: String::new(),
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

    pub fn sync_interactive(
        &mut self,
        selected_action_index: usize,
        input_mode: &str,
        pending_action: &str,
        input_buffer: &str,
        pending_reason: &str,
        input_feedback: &str,
        retry_available: bool,
        reason_sanitized_changed: bool,
    ) {
        self.selected_action_index = selected_action_index;
        self.selected_action = Action::all()
            .get(selected_action_index)
            .map(|action| action.action_id().to_string())
            .unwrap_or_else(|| Action::Refresh.action_id().to_string());
        self.input_mode = input_mode.to_string();
        self.pending_action = pending_action.to_string();
        let action = Action::from_action_id(pending_action);
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
        self.pending_reason = pending_reason.to_string();
        self.input_buffer = input_buffer.to_string();
        self.input_length = input_buffer.chars().count();
        self.input_matches_confirmation =
            !self.pending_confirmation.is_empty() && input_buffer == self.pending_confirmation;
        self.input_feedback = input_feedback.to_string();
        self.retry_or_cancel_available = retry_available;
        self.sanitized_reason_preview = sanitize_reason_preview(input_buffer);
        if !pending_reason.is_empty() && self.sanitized_reason_preview.is_empty() {
            self.sanitized_reason_preview = pending_reason.to_string();
        }
        self.reason_sanitized_changed = reason_sanitized_changed
            || (!input_buffer.is_empty() && self.sanitized_reason_preview != input_buffer.trim());
    }

    pub fn command_started(&mut self, command_id: u64, label: impl Into<String>) {
        self.active_command_id = Some(command_id);
        self.active_command_label = label.into();
        self.command_status = CommandStatus::Running;
        self.running_state_rendered = true;
    }

    pub fn apply_command_result(&mut self, result: OperatorCommandResult) {
        self.command_status = result.status;
        self.active_command_id = None;
        self.active_command_label.clear();
        self.artifact_paths = result.artifact_paths.clone();
        self.blockers = result.blockers.clone();
        self.warnings = result.warnings.clone();
        self.last_command_result = Some(result);
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
