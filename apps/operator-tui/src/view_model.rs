use serde::Serialize;

use crate::{
    actions::Action,
    commands::{CommandStatus, OperatorCommandResult},
    model::OperatorState,
    ui_layout::OperatorTab,
};

#[derive(Debug, Clone, Serialize)]
pub struct ViewModel {
    pub current_operator_state: OperatorState,
    pub selected_action: String,
    pub selected_action_index: usize,
    pub input_mode: String,
    pub pending_confirmation: String,
    pub pending_reason: String,
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
            pending_confirmation: String::new(),
            pending_reason: String::new(),
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
        pending_confirmation: &str,
        pending_reason: &str,
    ) {
        self.selected_action_index = selected_action_index;
        self.selected_action = Action::all()
            .get(selected_action_index)
            .map(|action| action.action_id().to_string())
            .unwrap_or_else(|| Action::Refresh.action_id().to_string());
        self.input_mode = input_mode.to_string();
        self.pending_confirmation = pending_confirmation.to_string();
        self.pending_reason = pending_reason.to_string();
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

fn value_or_none(value: &str) -> &str {
    if value.is_empty() {
        "none"
    } else {
        value
    }
}
