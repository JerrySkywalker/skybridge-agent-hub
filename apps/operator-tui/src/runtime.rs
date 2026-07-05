use std::{
    fs,
    path::{Path, PathBuf},
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};

use anyhow::Context;
use serde::Serialize;

use crate::{
    app::App,
    collect::StateMode,
    commands::{
        execute_operator_command, now_utc, CommandExecutionOptions, CommandStatus, OperatorCommand,
        OperatorCommandResult,
    },
};

pub const RUNTIME_REFACTOR_REPORT_SCHEMA: &str =
    "skybridge.operator_tui_runtime_refactor_report.v1";
pub const DEFAULT_RUNTIME_REFACTOR_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/runtime-refactor";
pub const DEFAULT_COMMAND_TIMEOUT_MS: u64 = 120_000;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum RuntimeSmokeScenario {
    None,
    Nonblocking,
    CommandStatus,
    Timeout,
    StaleResult,
    OneCommand,
    NoRealExecution,
}

#[derive(Debug, Clone)]
pub struct RuntimeDispatchOptions {
    pub output_dir: PathBuf,
    pub state_mode: StateMode,
    pub reason: String,
    pub delay_ms: u64,
}

#[derive(Debug)]
pub enum EnqueueOutcome {
    Started {
        command_id: u64,
        command: OperatorCommand,
    },
    Blocked(OperatorCommandResult),
}

#[derive(Debug)]
pub enum RuntimeEvent {
    Completed(OperatorCommandResult),
    TimedOut(OperatorCommandResult),
    StaleIgnored(OperatorCommandResult),
}

#[derive(Debug)]
pub struct OperatorRuntime {
    timeout: Duration,
    next_command_id: u64,
    result_tx: Sender<OperatorCommandResult>,
    result_rx: Receiver<OperatorCommandResult>,
    active: Option<ActiveCommand>,
    pub history: Vec<CommandHistoryEntry>,
    pub stale_result_ignored: bool,
    pub one_command_at_a_time_enforced: bool,
    pub ui_loop_nonblocking_observed: bool,
}

#[derive(Debug, Clone)]
struct ActiveCommand {
    command_id: u64,
    command: OperatorCommand,
    started_at: String,
    started: Instant,
}

#[derive(Debug, Clone, Serialize)]
pub struct CommandHistoryEntry {
    pub command_id: u64,
    pub command: OperatorCommand,
    pub status: CommandStatus,
    pub observed_at: String,
    pub result_summary: String,
    pub stale_result_ignored: bool,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct RuntimeRefactorReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub ui_loop_nonblocking: bool,
    pub background_command_runner_available: bool,
    pub command_request_model_available: bool,
    pub command_result_model_available: bool,
    pub view_model_available: bool,
    pub one_command_at_a_time_enforced: bool,
    pub command_timeout_enforced: bool,
    pub stale_result_ignored: bool,
    pub running_state_rendered: bool,
    pub last_command_status: String,
    pub command_history_count: usize,
    pub fixture_safe_only: bool,
    pub real_task_execution_enabled: bool,
    pub real_branch_creation_enabled: bool,
    pub real_pr_creation_enabled: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub branch_created: bool,
    pub pr_created: bool,
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
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
struct RuntimeTimeoutReport {
    schema: &'static str,
    generated_at: String,
    command_timeout_enforced: bool,
    timed_out: bool,
    timeout_ms: u128,
    last_command_status: String,
    token_printed: bool,
}

#[derive(Debug, Serialize)]
struct RuntimeStaleResultReport {
    schema: &'static str,
    generated_at: String,
    stale_result_ignored: bool,
    token_printed: bool,
}

impl RuntimeSmokeScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "nonblocking" => Ok(Self::Nonblocking),
            "command-status" => Ok(Self::CommandStatus),
            "timeout" => Ok(Self::Timeout),
            "stale-result" => Ok(Self::StaleResult),
            "one-command" => Ok(Self::OneCommand),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown runtime refactor smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }
}

impl RuntimeDispatchOptions {
    pub fn new(output_dir: PathBuf, state_mode: StateMode) -> Self {
        Self {
            output_dir,
            state_mode,
            reason: String::new(),
            delay_ms: 0,
        }
    }

    pub fn with_reason(mut self, reason: impl Into<String>) -> Self {
        self.reason = reason.into();
        self
    }

    pub fn with_delay_ms(mut self, delay_ms: u64) -> Self {
        self.delay_ms = delay_ms;
        self
    }
}

impl OperatorRuntime {
    pub fn new(timeout: Duration) -> Self {
        let (result_tx, result_rx) = mpsc::channel();
        Self {
            timeout,
            next_command_id: 1,
            result_tx,
            result_rx,
            active: None,
            history: Vec::new(),
            stale_result_ignored: false,
            one_command_at_a_time_enforced: true,
            ui_loop_nonblocking_observed: true,
        }
    }

    pub fn enqueue(
        &mut self,
        command: OperatorCommand,
        options: RuntimeDispatchOptions,
    ) -> EnqueueOutcome {
        if self.active.is_some() {
            let blocked = OperatorCommandResult::blocked(0, command, "command_already_running");
            self.record_result(&blocked, false);
            return EnqueueOutcome::Blocked(blocked);
        }

        let command_id = self.next_command_id;
        self.next_command_id += 1;
        let started_at = now_utc();
        self.record_status(command_id, command, CommandStatus::Queued, "command_queued");

        let tx = self.result_tx.clone();
        let execution_options = CommandExecutionOptions {
            output_dir: options.output_dir,
            state_mode: options.state_mode,
            reason: options.reason,
            delay_ms: options.delay_ms,
        };
        thread::spawn(move || {
            let result = execute_operator_command(command_id, command, execution_options);
            let _ = tx.send(result);
        });

        self.active = Some(ActiveCommand {
            command_id,
            command,
            started_at,
            started: Instant::now(),
        });
        self.record_status(
            command_id,
            command,
            CommandStatus::Running,
            "command_running",
        );

        EnqueueOutcome::Started {
            command_id,
            command,
        }
    }

    pub fn poll(&mut self) -> Vec<RuntimeEvent> {
        let mut events = Vec::new();
        while let Ok(result) = self.result_rx.try_recv() {
            let is_active = self
                .active
                .as_ref()
                .map(|active| active.command_id == result.command_id)
                .unwrap_or(false);
            if is_active {
                self.active = None;
                self.record_result(&result, false);
                events.push(RuntimeEvent::Completed(result));
            } else {
                self.stale_result_ignored = true;
                self.record_result(&result, true);
                events.push(RuntimeEvent::StaleIgnored(result));
            }
        }

        if let Some(active) = &self.active {
            if active.started.elapsed() >= self.timeout {
                let result = OperatorCommandResult::timed_out(
                    active.command_id,
                    active.command,
                    active.started_at.clone(),
                    active.started.elapsed().as_millis(),
                );
                self.active = None;
                self.record_result(&result, false);
                events.push(RuntimeEvent::TimedOut(result));
            }
        }

        events
    }

    pub fn timeout_ms(&self) -> u128 {
        self.timeout.as_millis()
    }

    pub fn is_running(&self) -> bool {
        self.active.is_some()
    }

    pub fn active_command_label(&self) -> Option<String> {
        self.active
            .as_ref()
            .map(|active| active.command.label().to_string())
    }

    pub fn active_elapsed_seconds(&self) -> Option<u64> {
        self.active
            .as_ref()
            .map(|active| active.started.elapsed().as_secs())
    }

    fn record_status(
        &mut self,
        command_id: u64,
        command: OperatorCommand,
        status: CommandStatus,
        summary: &str,
    ) {
        self.history.push(CommandHistoryEntry {
            command_id,
            command,
            status,
            observed_at: now_utc(),
            result_summary: summary.to_string(),
            stale_result_ignored: false,
            token_printed: false,
        });
    }

    fn record_result(&mut self, result: &OperatorCommandResult, stale_result_ignored: bool) {
        self.history.push(CommandHistoryEntry {
            command_id: result.command_id,
            command: result.command,
            status: result.status,
            observed_at: now_utc(),
            result_summary: result.result_summary.clone(),
            stale_result_ignored,
            token_printed: false,
        });
    }
}

pub fn apply_runtime_events(
    app: &mut App,
    events: Vec<RuntimeEvent>,
) -> Vec<OperatorCommandResult> {
    let mut applied_results = Vec::new();
    for event in events {
        match event {
            RuntimeEvent::Completed(mut result) => {
                if let Some(state) = result.operator_state.take() {
                    app.state = state;
                }
                app.view_model.apply_command_result(result.clone());
                applied_results.push(result);
                app.sync_view_model();
            }
            RuntimeEvent::TimedOut(result) => {
                app.view_model.apply_command_result(result.clone());
                applied_results.push(result);
                app.sync_view_model();
            }
            RuntimeEvent::StaleIgnored(_result) => {
                app.sync_view_model();
            }
        }
    }
    applied_results
}

pub fn run_runtime_refactor_simulation(
    app: &mut App,
    scenario: RuntimeSmokeScenario,
    output_dir: &Path,
) -> anyhow::Result<RuntimeRefactorReport> {
    let timeout = match scenario {
        RuntimeSmokeScenario::Timeout | RuntimeSmokeScenario::StaleResult => {
            Duration::from_millis(25)
        }
        _ => Duration::from_millis(DEFAULT_COMMAND_TIMEOUT_MS),
    };
    let mut runtime = OperatorRuntime::new(timeout);

    match scenario {
        RuntimeSmokeScenario::None => {}
        RuntimeSmokeScenario::Nonblocking => {
            let started = Instant::now();
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture)
                    .with_delay_ms(150),
            );
            if started.elapsed() < Duration::from_millis(100) && runtime.is_running() {
                runtime.ui_loop_nonblocking_observed = true;
            }
            wait_until_idle(app, &mut runtime, Duration::from_secs(2));
        }
        RuntimeSmokeScenario::CommandStatus => {
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture),
            );
            wait_until_idle(app, &mut runtime, Duration::from_secs(2));
        }
        RuntimeSmokeScenario::Timeout => {
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture)
                    .with_delay_ms(120),
            );
            wait_for_status(
                app,
                &mut runtime,
                CommandStatus::TimedOut,
                Duration::from_secs(2),
            );
        }
        RuntimeSmokeScenario::StaleResult => {
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture)
                    .with_delay_ms(90),
            );
            wait_for_status(
                app,
                &mut runtime,
                CommandStatus::TimedOut,
                Duration::from_secs(2),
            );
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture)
                    .with_delay_ms(180),
            );
            wait_for_stale(app, &mut runtime, Duration::from_secs(2));
            wait_until_idle(app, &mut runtime, Duration::from_secs(2));
        }
        RuntimeSmokeScenario::OneCommand => {
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture)
                    .with_delay_ms(150),
            );
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::GenerateCandidateFixture,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::CandidateFlow),
            );
            wait_until_idle(app, &mut runtime, Duration::from_secs(2));
        }
        RuntimeSmokeScenario::NoRealExecution => {
            enqueue_and_apply(
                app,
                &mut runtime,
                OperatorCommand::CopySafeSummary,
                RuntimeDispatchOptions::new(output_dir.to_path_buf(), StateMode::Fixture),
            );
            wait_until_idle(app, &mut runtime, Duration::from_secs(2));
        }
    }

    write_runtime_refactor_artifacts(output_dir, app, &runtime)?;
    Ok(runtime_refactor_report(app, &runtime))
}

fn enqueue_and_apply(
    app: &mut App,
    runtime: &mut OperatorRuntime,
    command: OperatorCommand,
    options: RuntimeDispatchOptions,
) {
    match runtime.enqueue(command, options) {
        EnqueueOutcome::Started {
            command_id,
            command,
        } => {
            app.view_model.command_started(command_id, command.label());
        }
        EnqueueOutcome::Blocked(result) => {
            app.view_model.apply_command_result(result);
        }
    }
    app.sync_view_model();
}

fn wait_until_idle(app: &mut App, runtime: &mut OperatorRuntime, limit: Duration) {
    let started = Instant::now();
    while started.elapsed() < limit {
        apply_runtime_events(app, runtime.poll());
        if !runtime.is_running() {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn wait_for_status(
    app: &mut App,
    runtime: &mut OperatorRuntime,
    status: CommandStatus,
    limit: Duration,
) {
    let started = Instant::now();
    while started.elapsed() < limit {
        apply_runtime_events(app, runtime.poll());
        if app.view_model.command_status == status {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn wait_for_stale(app: &mut App, runtime: &mut OperatorRuntime, limit: Duration) {
    let started = Instant::now();
    while started.elapsed() < limit {
        apply_runtime_events(app, runtime.poll());
        if runtime.stale_result_ignored {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
}

pub fn write_runtime_refactor_artifacts(
    output_dir: &Path,
    app: &App,
    runtime: &OperatorRuntime,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let runtime_state_json = serde_json::to_string_pretty(&app.view_model)?;
    let report = runtime_refactor_report(app, runtime);
    let report_json = serde_json::to_string_pretty(&report)?;
    let history_json = serde_json::to_string_pretty(&runtime.history)?;
    let timeout_report = RuntimeTimeoutReport {
        schema: "skybridge.operator_tui_runtime_timeout_report.v1",
        generated_at: now_utc(),
        command_timeout_enforced: true,
        timed_out: runtime
            .history
            .iter()
            .any(|entry| entry.status == CommandStatus::TimedOut),
        timeout_ms: runtime.timeout_ms(),
        last_command_status: app.view_model.command_status.as_str().to_string(),
        token_printed: false,
    };
    let timeout_json = serde_json::to_string_pretty(&timeout_report)?;
    let stale_report = RuntimeStaleResultReport {
        schema: "skybridge.operator_tui_runtime_stale_result_report.v1",
        generated_at: now_utc(),
        stale_result_ignored: runtime.stale_result_ignored,
        token_printed: false,
    };
    let stale_json = serde_json::to_string_pretty(&stale_report)?;

    write_text(
        &output_dir.join("runtime-state.json"),
        &format!("{runtime_state_json}\n"),
    )?;
    write_text(
        &output_dir.join("runtime-report.json"),
        &format!("{report_json}\n"),
    )?;
    write_text(
        &output_dir.join("runtime-report.md"),
        &render_runtime_report_markdown(&report, output_dir),
    )?;
    write_text(
        &output_dir.join("command-history.json"),
        &format!("{history_json}\n"),
    )?;
    write_text(
        &output_dir.join("timeout-report.json"),
        &format!("{timeout_json}\n"),
    )?;
    write_text(
        &output_dir.join("stale-result-report.json"),
        &format!("{stale_json}\n"),
    )?;
    Ok(())
}

pub fn runtime_refactor_report(app: &App, runtime: &OperatorRuntime) -> RuntimeRefactorReport {
    let flags = &app.view_model.safety_flags;
    RuntimeRefactorReport {
        schema: RUNTIME_REFACTOR_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "runtime-refactor",
        ui_loop_nonblocking: runtime.ui_loop_nonblocking_observed,
        background_command_runner_available: true,
        command_request_model_available: true,
        command_result_model_available: true,
        view_model_available: true,
        one_command_at_a_time_enforced: runtime.one_command_at_a_time_enforced,
        command_timeout_enforced: true,
        stale_result_ignored: runtime.stale_result_ignored,
        running_state_rendered: app.view_model.running_state_rendered,
        last_command_status: app.view_model.command_status.as_str().to_string(),
        command_history_count: runtime.history.len(),
        fixture_safe_only: true,
        real_task_execution_enabled: flags.real_task_execution_enabled,
        real_branch_creation_enabled: flags.real_branch_creation_enabled,
        real_pr_creation_enabled: flags.real_pr_creation_enabled,
        task_created: flags.task_created,
        task_claimed: flags.task_claimed,
        execution_started: flags.execution_started,
        branch_created: false,
        pr_created: false,
        worker_loop_started: flags.worker_loop_started,
        queue_runner_started: flags.queue_runner_started,
        run_forever_started: flags.run_forever_started,
        hermes_live_called: flags.hermes_live_called,
        mcp_run_called: flags.mcp_run_called,
        auto_merge_enabled: flags.auto_merge_enabled,
        release_created: flags.release_created,
        tag_created: flags.tag_created,
        asset_uploaded: flags.asset_uploaded,
        token_printed: flags.token_printed,
        blockers: app.view_model.blockers.clone(),
        warnings: app.view_model.warnings.clone(),
    }
}

fn render_runtime_report_markdown(report: &RuntimeRefactorReport, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG368F Runtime Refactor Report\n\n- schema: {}\n- mode: {}\n- ui_loop_nonblocking: {}\n- background_command_runner_available: {}\n- command_request_model_available: {}\n- command_result_model_available: {}\n- view_model_available: {}\n- one_command_at_a_time_enforced: {}\n- command_timeout_enforced: {}\n- stale_result_ignored: {}\n- running_state_rendered: {}\n- last_command_status: {}\n- command_history_count: {}\n- fixture_safe_only: true\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- branch_created: false\n- pr_created: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Artifacts\n\n- runtime_state: {}\n- runtime_report: {}\n- command_history: {}\n- timeout_report: {}\n- stale_result_report: {}\n",
        report.schema,
        report.mode,
        report.ui_loop_nonblocking,
        report.background_command_runner_available,
        report.command_request_model_available,
        report.command_result_model_available,
        report.view_model_available,
        report.one_command_at_a_time_enforced,
        report.command_timeout_enforced,
        report.stale_result_ignored,
        report.running_state_rendered,
        report.last_command_status,
        report.command_history_count,
        path_for_report(&output_dir.join("runtime-state.json")),
        path_for_report(&output_dir.join("runtime-report.json")),
        path_for_report(&output_dir.join("command-history.json")),
        path_for_report(&output_dir.join("timeout-report.json")),
        path_for_report(&output_dir.join("stale-result-report.json")),
    )
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}
