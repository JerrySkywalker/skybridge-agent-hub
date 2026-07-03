use std::{path::PathBuf, thread, time::Instant};

use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::{
    actions::Action,
    app::{App, Cli},
    candidate::{CandidateAction, APPEND_CONFIRMATION, REVIEW_CONFIRMATION},
    collect::StateMode,
    model::OperatorState,
    single_step::{SingleStepAction, ABORT_CONFIRMATION, PAUSE_CONFIRMATION, START_CONFIRMATION},
};

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OperatorCommand {
    RefreshLocalCloud,
    GenerateCandidateFixture,
    ValidateCandidate,
    ReviewCandidate,
    AppendCandidate,
    PreviewBoundedAction,
    StartOneFixture,
    SafePauseFixture,
    AbortPreview,
    CopySafeSummary,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CommandStatus {
    Idle,
    Queued,
    Running,
    Completed,
    Blocked,
    Failed,
    TimedOut,
}

#[derive(Debug, Clone)]
pub struct CommandExecutionOptions {
    pub output_dir: PathBuf,
    pub state_mode: StateMode,
    pub reason: String,
    pub delay_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct OperatorCommandResult {
    pub command_id: u64,
    pub command: OperatorCommand,
    pub status: CommandStatus,
    pub started_at: String,
    pub finished_at: String,
    pub duration_ms: u128,
    pub result_summary: String,
    pub artifact_paths: Vec<String>,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
    pub token_printed: bool,
    #[serde(skip_serializing)]
    pub operator_state: Option<OperatorState>,
}

impl OperatorCommand {
    pub fn from_action(action: Action) -> Option<Self> {
        match action {
            Action::Refresh => Some(Self::RefreshLocalCloud),
            Action::GenerateCandidateFixture => Some(Self::GenerateCandidateFixture),
            Action::ValidateCandidate => Some(Self::ValidateCandidate),
            Action::ReviewCandidate => Some(Self::ReviewCandidate),
            Action::AppendCandidate => Some(Self::AppendCandidate),
            Action::PreviewBoundedAction => Some(Self::PreviewBoundedAction),
            Action::StartOneGoal => Some(Self::StartOneFixture),
            Action::SafePause => Some(Self::SafePauseFixture),
            Action::AbortTerminate => Some(Self::AbortPreview),
            Action::CopySafeSummary => Some(Self::CopySafeSummary),
            Action::Quit => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::RefreshLocalCloud => "Refresh local/cloud",
            Self::GenerateCandidateFixture => "Generate candidate fixture",
            Self::ValidateCandidate => "Validate candidate",
            Self::ReviewCandidate => "Review candidate",
            Self::AppendCandidate => "Append candidate",
            Self::PreviewBoundedAction => "Preview bounded action",
            Self::StartOneFixture => "Start one fixture",
            Self::SafePauseFixture => "Safe pause fixture",
            Self::AbortPreview => "Abort preview",
            Self::CopySafeSummary => "Copy safe summary",
        }
    }

    fn state_mode(self, fallback: StateMode) -> StateMode {
        match self {
            Self::RefreshLocalCloud => StateMode::LocalCloud,
            Self::GenerateCandidateFixture
            | Self::ValidateCandidate
            | Self::ReviewCandidate
            | Self::AppendCandidate => StateMode::CandidateFlow,
            Self::PreviewBoundedAction
            | Self::StartOneFixture
            | Self::SafePauseFixture
            | Self::AbortPreview => StateMode::SingleStep,
            Self::CopySafeSummary => fallback,
        }
    }
}

impl CommandStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Queued => "queued",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Blocked => "blocked",
            Self::Failed => "failed",
            Self::TimedOut => "timed_out",
        }
    }
}

impl OperatorCommandResult {
    pub fn blocked(command_id: u64, command: OperatorCommand, reason: impl Into<String>) -> Self {
        let now = now_utc();
        let reason = reason.into();
        Self {
            command_id,
            command,
            status: CommandStatus::Blocked,
            started_at: now.clone(),
            finished_at: now,
            duration_ms: 0,
            result_summary: reason.clone(),
            artifact_paths: Vec::new(),
            blockers: vec![reason],
            warnings: Vec::new(),
            token_printed: false,
            operator_state: None,
        }
    }

    pub fn timed_out(
        command_id: u64,
        command: OperatorCommand,
        started_at: String,
        duration_ms: u128,
    ) -> Self {
        Self {
            command_id,
            command,
            status: CommandStatus::TimedOut,
            started_at,
            finished_at: now_utc(),
            duration_ms,
            result_summary: "command_timed_out".to_string(),
            artifact_paths: Vec::new(),
            blockers: vec!["command_timed_out".to_string()],
            warnings: vec!["stale_result_will_be_ignored_if_it_arrives_later".to_string()],
            token_printed: false,
            operator_state: None,
        }
    }
}

pub fn execute_operator_command(
    command_id: u64,
    command: OperatorCommand,
    options: CommandExecutionOptions,
) -> OperatorCommandResult {
    let started_at = now_utc();
    let started = Instant::now();

    if options.delay_ms > 0 {
        thread::sleep(std::time::Duration::from_millis(options.delay_ms));
    }

    let result = execute_operator_command_inner(command, &options);
    let finished_at = now_utc();
    let duration_ms = started.elapsed().as_millis();

    match result {
        Ok(app) => {
            let (status, blockers, warnings, summary) = summarize_command_result(command, &app);
            OperatorCommandResult {
                command_id,
                command,
                status,
                started_at,
                finished_at,
                duration_ms,
                result_summary: summary,
                artifact_paths: artifact_paths(command, &options.output_dir),
                blockers,
                warnings,
                token_printed: false,
                operator_state: Some(app.state),
            }
        }
        Err(reason) => OperatorCommandResult {
            command_id,
            command,
            status: CommandStatus::Failed,
            started_at,
            finished_at,
            duration_ms,
            result_summary: reason.clone(),
            artifact_paths: Vec::new(),
            blockers: vec![reason],
            warnings: Vec::new(),
            token_printed: false,
            operator_state: None,
        },
    }
}

fn execute_operator_command_inner(
    command: OperatorCommand,
    options: &CommandExecutionOptions,
) -> Result<App, String> {
    let state_mode = command.state_mode(options.state_mode);
    let mut app = App::new(state_mode, &options.output_dir);

    match command {
        OperatorCommand::RefreshLocalCloud => {
            app.state_mode = StateMode::LocalCloud;
            app.refresh_state(&options.output_dir);
            app.write_snapshot_artifacts(&options.output_dir)
                .map_err(|_| "refresh_artifact_write_failed".to_string())?;
        }
        OperatorCommand::CopySafeSummary => {
            app.write_snapshot_artifacts(&options.output_dir)
                .map_err(|_| "safe_summary_write_failed".to_string())?;
        }
        OperatorCommand::GenerateCandidateFixture => {
            run_candidate(
                &mut app,
                &options.output_dir,
                CandidateAction::Generate,
                "",
                "",
            )?;
        }
        OperatorCommand::ValidateCandidate => {
            run_candidate(
                &mut app,
                &options.output_dir,
                CandidateAction::Validate,
                "",
                "",
            )?;
        }
        OperatorCommand::ReviewCandidate => {
            run_candidate(
                &mut app,
                &options.output_dir,
                CandidateAction::ReviewApprove,
                REVIEW_CONFIRMATION,
                "",
            )?;
        }
        OperatorCommand::AppendCandidate => {
            run_candidate(
                &mut app,
                &options.output_dir,
                CandidateAction::AppendPreview,
                "",
                "",
            )?;
            run_candidate(
                &mut app,
                &options.output_dir,
                CandidateAction::AppendApplyFixture,
                "",
                APPEND_CONFIRMATION,
            )?;
        }
        OperatorCommand::PreviewBoundedAction => {
            run_single_step(
                &mut app,
                &options.output_dir,
                SingleStepAction::PreviewBoundedAction,
                "",
                "",
                "",
                "",
                "",
            )?;
        }
        OperatorCommand::StartOneFixture => {
            run_single_step(
                &mut app,
                &options.output_dir,
                SingleStepAction::StartOneFixture,
                START_CONFIRMATION,
                "",
                "",
                "",
                "",
            )?;
        }
        OperatorCommand::SafePauseFixture => {
            run_single_step(
                &mut app,
                &options.output_dir,
                SingleStepAction::SafePause,
                "",
                PAUSE_CONFIRMATION,
                "",
                &options.reason,
                "",
            )?;
        }
        OperatorCommand::AbortPreview => {
            run_single_step(
                &mut app,
                &options.output_dir,
                SingleStepAction::AbortPreview,
                "",
                "",
                ABORT_CONFIRMATION,
                "",
                &options.reason,
            )?;
        }
    }

    Ok(app)
}

fn run_candidate(
    app: &mut App,
    output_dir: &std::path::Path,
    action: CandidateAction,
    review_confirm: &str,
    append_confirm: &str,
) -> Result<(), String> {
    let mut cli = Cli::default();
    cli.state_mode = StateMode::CandidateFlow;
    cli.output_dir = output_dir.to_path_buf();
    cli.output_dir_provided = true;
    cli.candidate_action = action;
    cli.review_confirm = review_confirm.to_string();
    cli.append_confirm = append_confirm.to_string();
    app.state_mode = StateMode::CandidateFlow;
    app.refresh_state(output_dir);
    app.run_candidate_action(&cli);
    app.write_snapshot_artifacts(output_dir)
        .map_err(|_| "candidate_artifact_write_failed".to_string())
}

fn run_single_step(
    app: &mut App,
    output_dir: &std::path::Path,
    action: SingleStepAction,
    start_confirm: &str,
    pause_confirm: &str,
    abort_confirm: &str,
    pause_reason: &str,
    abort_reason: &str,
) -> Result<(), String> {
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
    app.state_mode = StateMode::SingleStep;
    app.refresh_state(output_dir);
    app.run_single_step_action(&cli);
    app.write_snapshot_artifacts(output_dir)
        .map_err(|_| "single_step_artifact_write_failed".to_string())
}

fn summarize_command_result(
    command: OperatorCommand,
    app: &App,
) -> (CommandStatus, Vec<String>, Vec<String>, String) {
    match command {
        OperatorCommand::GenerateCandidateFixture
        | OperatorCommand::ValidateCandidate
        | OperatorCommand::ReviewCandidate
        | OperatorCommand::AppendCandidate => {
            let candidate = &app.state.candidate_flow;
            let blockers = candidate.validation_blockers.clone();
            let warnings = candidate.validation_warnings.clone();
            if blockers.is_empty() {
                (
                    CommandStatus::Completed,
                    blockers,
                    warnings,
                    "candidate_command_completed_fixture_safe".to_string(),
                )
            } else {
                (
                    CommandStatus::Blocked,
                    blockers,
                    warnings,
                    "candidate_command_blocked".to_string(),
                )
            }
        }
        OperatorCommand::PreviewBoundedAction
        | OperatorCommand::StartOneFixture
        | OperatorCommand::SafePauseFixture
        | OperatorCommand::AbortPreview => {
            let step = &app.state.single_step;
            let blockers = step.next_bounded_action_blockers.clone();
            let warnings = if step.start_one_performed {
                vec!["fixture_single_step_gate_exercised_no_real_execution".to_string()]
            } else {
                Vec::new()
            };
            if blockers.is_empty()
                || matches!(
                    command,
                    OperatorCommand::PreviewBoundedAction | OperatorCommand::AbortPreview
                )
            {
                (
                    CommandStatus::Completed,
                    blockers,
                    warnings,
                    "single_step_command_completed_fixture_safe".to_string(),
                )
            } else {
                (
                    CommandStatus::Blocked,
                    blockers,
                    warnings,
                    "single_step_command_blocked".to_string(),
                )
            }
        }
        OperatorCommand::RefreshLocalCloud | OperatorCommand::CopySafeSummary => (
            CommandStatus::Completed,
            app.state.campaign.blockers.clone(),
            app.state.campaign.warnings.clone(),
            "operator_state_command_completed".to_string(),
        ),
    }
}

fn artifact_paths(command: OperatorCommand, output_dir: &std::path::Path) -> Vec<String> {
    let names: &[&str] = match command {
        OperatorCommand::GenerateCandidateFixture
        | OperatorCommand::ValidateCandidate
        | OperatorCommand::ReviewCandidate
        | OperatorCommand::AppendCandidate => &[
            "operator-tui-candidate-state.json",
            "operator-tui-candidate-report.json",
            "operator-tui-candidate-report.md",
            "generated-candidate.md",
        ],
        OperatorCommand::PreviewBoundedAction
        | OperatorCommand::StartOneFixture
        | OperatorCommand::SafePauseFixture
        | OperatorCommand::AbortPreview => &[
            "operator-tui-single-step-state.json",
            "operator-tui-single-step-report.json",
            "operator-tui-single-step-report.md",
            "operator-tui-single-step-preview.json",
        ],
        OperatorCommand::RefreshLocalCloud | OperatorCommand::CopySafeSummary => &[
            "operator-tui-state.json",
            "operator-tui-report.json",
            "operator-tui-report.md",
            "operator-tui-snapshot.txt",
        ],
    };

    names
        .iter()
        .map(|name| output_dir.join(name).to_string_lossy().replace('\\', "/"))
        .collect()
}

pub fn now_utc() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}
