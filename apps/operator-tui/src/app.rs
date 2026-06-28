use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;

use crate::{
    actions::{active_action_statuses, disabled_action_statuses},
    collect::{collect_operator_state, StateMode},
    model::{OperatorReport, OperatorState, REPORT_SCHEMA, STATE_SCHEMA},
    render::{render_report_markdown, render_snapshot_text, PANELS},
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
        }
    }
}

#[derive(Debug, Clone)]
pub struct App {
    pub state: OperatorState,
    pub state_mode: StateMode,
}

impl App {
    pub fn new(state_mode: StateMode) -> Self {
        Self {
            state: collect_operator_state(state_mode),
            state_mode,
        }
    }

    pub fn refresh_state(&mut self) {
        self.state = collect_operator_state(self.state_mode);
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
            "--snapshot" => cli.snapshot = true,
            "--json" => cli.json = true,
            "--write-report" => cli.write_report = true,
            "--no-alt-screen" => cli.no_alt_screen = true,
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
