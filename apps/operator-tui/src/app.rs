use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;

use crate::{
    actions::{active_action_statuses, disabled_action_statuses},
    candidate::{
        candidate_report, load_candidate_state, run_candidate_action, write_candidate_artifacts,
        CandidateAction, CandidateFlowOptions,
    },
    collect::{collect_operator_state, StateMode},
    model::{OperatorReport, OperatorState, REPORT_SCHEMA, STATE_SCHEMA},
    render::{render_report_markdown, render_snapshot_text, PANELS},
    single_step::{
        load_default_candidate_state, load_single_step_state, run_single_step_action,
        single_step_report, write_single_step_artifacts, SingleStepAction, SingleStepOptions,
        DEFAULT_SINGLE_STEP_OUTPUT_DIR,
    },
};

#[derive(Debug, Clone)]
pub struct Cli {
    pub state_mode: StateMode,
    pub snapshot: bool,
    pub json: bool,
    pub write_report: bool,
    pub output_dir: PathBuf,
    pub output_dir_provided: bool,
    pub no_alt_screen: bool,
    pub candidate_action: CandidateAction,
    pub review_confirm: String,
    pub append_confirm: String,
    pub single_step_action: SingleStepAction,
    pub single_step_mode: String,
    pub start_confirm: String,
    pub pause_confirm: String,
    pub abort_confirm: String,
    pub pause_reason: String,
    pub abort_reason: String,
}

impl Default for Cli {
    fn default() -> Self {
        Self {
            state_mode: StateMode::Fixture,
            snapshot: false,
            json: false,
            write_report: false,
            output_dir: PathBuf::from(".agent/tmp/operator-tui"),
            output_dir_provided: false,
            no_alt_screen: false,
            candidate_action: CandidateAction::None,
            review_confirm: String::new(),
            append_confirm: String::new(),
            single_step_action: SingleStepAction::None,
            single_step_mode: "fixture".to_string(),
            start_confirm: String::new(),
            pause_confirm: String::new(),
            abort_confirm: String::new(),
            pause_reason: String::new(),
            abort_reason: String::new(),
        }
    }
}

impl Cli {
    pub fn artifact_output_dir(&self) -> PathBuf {
        if self.output_dir_provided {
            return self.output_dir.clone();
        }

        match self.state_mode {
            StateMode::Fixture => PathBuf::from(".agent/tmp/operator-tui"),
            StateMode::Local => PathBuf::from(".agent/tmp/operator-tui/local"),
            StateMode::Cloud => PathBuf::from(".agent/tmp/operator-tui/cloud"),
            StateMode::LocalCloud => PathBuf::from(".agent/tmp/operator-tui/local-cloud"),
            StateMode::CandidateFlow => PathBuf::from(".agent/tmp/operator-tui/candidate-flow"),
            StateMode::SingleStep => PathBuf::from(DEFAULT_SINGLE_STEP_OUTPUT_DIR),
        }
    }
}

#[derive(Debug, Clone)]
pub struct App {
    pub state: OperatorState,
    pub state_mode: StateMode,
}

impl App {
    pub fn new(state_mode: StateMode, output_dir: &Path) -> Self {
        let mut state = collect_operator_state(state_mode);
        if state_mode == StateMode::SingleStep {
            state.candidate_flow = load_default_candidate_state();
            state.single_step = load_single_step_state(output_dir);
        } else {
            state.candidate_flow = load_candidate_state(output_dir);
        }
        Self { state, state_mode }
    }

    pub fn refresh_state(&mut self, output_dir: &Path) {
        self.state = collect_operator_state(self.state_mode);
        if self.state_mode == StateMode::SingleStep {
            self.state.candidate_flow = load_default_candidate_state();
            self.state.single_step = load_single_step_state(output_dir);
        } else {
            self.state.candidate_flow = load_candidate_state(output_dir);
        }
    }

    pub fn run_candidate_action(&mut self, cli: &Cli) {
        let output_dir = cli.artifact_output_dir();
        let options = CandidateFlowOptions {
            output_dir,
            action: cli.candidate_action,
            review_confirm: cli.review_confirm.clone(),
            append_confirm: cli.append_confirm.clone(),
        };
        self.state.candidate_flow = run_candidate_action(&options);
    }

    pub fn run_single_step_action(&mut self, cli: &Cli) {
        let output_dir = cli.artifact_output_dir();
        let options = SingleStepOptions {
            output_dir,
            action: cli.single_step_action,
            mode: cli.single_step_mode.clone(),
            start_confirm: cli.start_confirm.clone(),
            pause_confirm: cli.pause_confirm.clone(),
            abort_confirm: cli.abort_confirm.clone(),
            pause_reason: cli.pause_reason.clone(),
            abort_reason: cli.abort_reason.clone(),
        };
        self.state.single_step = run_single_step_action(&options, &self.state);
    }

    pub fn report(&self, interactive_started: bool) -> OperatorReport {
        let safety = &self.state.safety;
        OperatorReport {
            schema: REPORT_SCHEMA,
            generated_at: self.state.generated_at.clone(),
            mode: self.state.mode.clone(),
            fixture_used: self.state.mode == "fixture",
            interactive_started,
            state_schema: STATE_SCHEMA,
            local_state_loaded: self.state.local_state_loaded,
            cloud_state_loaded: self.state.cloud_state_loaded,
            local_cloud_parity_checked: self.state.mode == "local-cloud"
                && self.state.cloud_state_loaded,
            panels_rendered: PANELS.to_vec(),
            disabled_actions: disabled_action_statuses(),
            active_actions: active_action_statuses(),
            mutation_attempted: safety.mutation_attempted,
            append_attempted: safety.append_attempted,
            approval_attempted: safety.approval_attempted,
            task_created: safety.task_created,
            task_claimed: safety.task_claimed,
            execution_started: safety.execution_started,
            branch_created: safety.branch_created,
            pr_created: safety.pr_created,
            merge_performed: safety.merge_performed,
            deploy_triggered: safety.deploy_triggered,
            worker_loop_started: safety.worker_loop_started,
            queue_runner_started: safety.queue_runner_started,
            hermes_live_called: safety.hermes_live_called,
            mcp_run_called: safety.mcp_run_called,
            token_printed: safety.token_printed,
            blockers: self.state.campaign.blockers.clone(),
            warnings: self.state.campaign.warnings.clone(),
        }
    }

    pub fn snapshot_text(&self) -> String {
        render_snapshot_text(&self.state)
    }

    pub fn write_snapshot_artifacts(&self, output_dir: &Path) -> anyhow::Result<()> {
        fs::create_dir_all(output_dir)
            .with_context(|| format!("failed to create {}", output_dir.display()))?;

        let snapshot_path = output_dir.join("operator-tui-snapshot.txt");
        let state_path = output_dir.join("operator-tui-state.json");
        let report_json_path = output_dir.join("operator-tui-report.json");
        let report_md_path = output_dir.join("operator-tui-report.md");

        let snapshot_text = self.snapshot_text();
        if self.state_mode == StateMode::CandidateFlow {
            return write_candidate_artifacts(output_dir, &self.state, &snapshot_text);
        }
        if self.state_mode == StateMode::SingleStep {
            return write_single_step_artifacts(output_dir, &self.state, &snapshot_text);
        }

        let state_json = serde_json::to_string_pretty(&self.state)?;
        let report = self.report(false);
        let report_json = serde_json::to_string_pretty(&report)?;
        let report_md = render_report_markdown(
            self,
            &path_for_report(&snapshot_path),
            &path_for_report(&state_path),
        );

        fs::write(&snapshot_path, snapshot_text)
            .with_context(|| format!("failed to write {}", snapshot_path.display()))?;
        fs::write(&state_path, format!("{state_json}\n"))
            .with_context(|| format!("failed to write {}", state_path.display()))?;
        fs::write(&report_json_path, format!("{report_json}\n"))
            .with_context(|| format!("failed to write {}", report_json_path.display()))?;
        fs::write(&report_md_path, report_md)
            .with_context(|| format!("failed to write {}", report_md_path.display()))?;

        Ok(())
    }

    pub fn report_json(&self, interactive_started: bool) -> anyhow::Result<String> {
        if self.state_mode == StateMode::CandidateFlow {
            return Ok(serde_json::to_string_pretty(&candidate_report(
                &self.state,
            ))?);
        }
        if self.state_mode == StateMode::SingleStep {
            return Ok(serde_json::to_string_pretty(&single_step_report(
                &self.state,
            ))?);
        }
        Ok(serde_json::to_string_pretty(
            &self.report(interactive_started),
        )?)
    }
}

pub fn parse_cli(args: impl IntoIterator<Item = String>) -> anyhow::Result<Cli> {
    let mut cli = Cli::default();
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--fixture" => cli.state_mode = StateMode::Fixture,
            "--local" => cli.state_mode = StateMode::Local,
            "--cloud" => cli.state_mode = StateMode::Cloud,
            "--local-cloud" => cli.state_mode = StateMode::LocalCloud,
            "--candidate-flow" => cli.state_mode = StateMode::CandidateFlow,
            "--single-step" => cli.state_mode = StateMode::SingleStep,
            "--snapshot" => cli.snapshot = true,
            "--json" => cli.json = true,
            "--write-report" => cli.write_report = true,
            "--no-alt-screen" => cli.no_alt_screen = true,
            "--candidate-action" => {
                let value = iter
                    .next()
                    .context("--candidate-action requires a following value")?;
                cli.candidate_action = CandidateAction::from_str(&value)?;
                cli.state_mode = StateMode::CandidateFlow;
            }
            "--single-step-action" => {
                let value = iter
                    .next()
                    .context("--single-step-action requires a following value")?;
                cli.single_step_action = SingleStepAction::from_str(&value)?;
                cli.state_mode = StateMode::SingleStep;
            }
            "--single-step-mode" => {
                cli.single_step_mode = iter
                    .next()
                    .context("--single-step-mode requires a following value")?;
                cli.state_mode = StateMode::SingleStep;
            }
            "--review-confirm" => {
                cli.review_confirm = iter
                    .next()
                    .context("--review-confirm requires a following value")?;
            }
            "--append-confirm" => {
                cli.append_confirm = iter
                    .next()
                    .context("--append-confirm requires a following value")?;
            }
            "--start-confirm" => {
                cli.start_confirm = iter
                    .next()
                    .context("--start-confirm requires a following value")?;
            }
            "--pause-confirm" => {
                cli.pause_confirm = iter
                    .next()
                    .context("--pause-confirm requires a following value")?;
            }
            "--abort-confirm" => {
                cli.abort_confirm = iter
                    .next()
                    .context("--abort-confirm requires a following value")?;
            }
            "--pause-reason" => {
                cli.pause_reason = iter
                    .next()
                    .context("--pause-reason requires a following value")?;
            }
            "--abort-reason" => {
                cli.abort_reason = iter
                    .next()
                    .context("--abort-reason requires a following value")?;
            }
            "--output-dir" => {
                let value = iter
                    .next()
                    .context("--output-dir requires a following path")?;
                cli.output_dir = PathBuf::from(value);
                cli.output_dir_provided = true;
            }
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            other => anyhow::bail!("unknown argument: {other}"),
        }
    }
    Ok(cli)
}

pub fn print_help() {
    println!(
        "skybridge-operator-tui -- read-only Ratatui operator console\n\
\n\
Flags:\n\
  --fixture              Use deterministic fixture state (default)\n\
  --local                Read local repository state only\n\
  --cloud                Read cloud health/version/parity state only\n\
  --local-cloud          Read both local repository and cloud state\n\
  --candidate-flow       Use MG368C candidate review/append monitor mode\n\
  --candidate-action <a> Run generate, validate, review-preview, review-approve,\n\
                         append-preview, or append-apply-fixture\n\
  --review-confirm <s>   Exact review confirmation for review-approve\n\
  --append-confirm <s>   Exact append confirmation for append-apply-fixture\n\
  --single-step          Use MG368D single-step gate mode\n\
  --single-step-action <a>\n\
                         Run preview, start-fixture, safe-pause, abort-preview,\n\
                         or abort-apply-fixture\n\
  --single-step-mode <m> Use fixture, preview, or manual metadata mode\n\
  --start-confirm <s>    Exact confirmation for start-fixture\n\
  --pause-confirm <s>    Exact confirmation for safe-pause\n\
  --abort-confirm <s>    Exact confirmation for abort-apply-fixture\n\
  --pause-reason <s>     Sanitized reason for safe-pause\n\
  --abort-reason <s>     Sanitized reason for abort preview/apply\n\
  --snapshot             Render non-interactive snapshot artifacts\n\
  --json                 Print report JSON to stdout\n\
  --write-report         Write report artifacts under --output-dir\n\
  --output-dir <path>    Artifact directory (default .agent/tmp/operator-tui, or mode subdir)\n\
  --no-alt-screen        Do not enter alternate screen in interactive mode\n"
    );
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}
