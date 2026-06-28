use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;

use crate::{
    actions::{active_action_statuses, disabled_action_statuses},
    model::{
        fixture_state, OperatorReport, OperatorState, FIXTURE_GENERATED_AT, REPORT_SCHEMA,
        STATE_SCHEMA,
    },
    render::{render_report_markdown, render_snapshot_text, PANELS},
};

#[derive(Debug, Clone)]
pub struct Cli {
    pub fixture: bool,
    pub snapshot: bool,
    pub json: bool,
    pub write_report: bool,
    pub output_dir: PathBuf,
    pub no_alt_screen: bool,
}

impl Default for Cli {
    fn default() -> Self {
        Self {
            fixture: true,
            snapshot: false,
            json: false,
            write_report: false,
            output_dir: PathBuf::from(".agent/tmp/operator-tui"),
            no_alt_screen: false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct App {
    pub state: OperatorState,
}

impl App {
    pub fn fixture() -> Self {
        Self {
            state: fixture_state(),
        }
    }

    pub fn refresh_fixture_state(&mut self) {
        self.state = fixture_state();
    }

    pub fn report(&self, mode: impl Into<String>, interactive_started: bool) -> OperatorReport {
        OperatorReport {
            schema: REPORT_SCHEMA,
            generated_at: FIXTURE_GENERATED_AT,
            mode: mode.into(),
            fixture_used: self.state.mode == "fixture",
            interactive_started,
            state_schema: STATE_SCHEMA,
            panels_rendered: PANELS.to_vec(),
            disabled_actions: disabled_action_statuses(),
            active_actions: active_action_statuses(),
            mutation_attempted: false,
            append_attempted: false,
            approval_attempted: false,
            task_created: false,
            task_claimed: false,
            execution_started: false,
            branch_created: false,
            pr_created: false,
            merge_performed: false,
            deploy_triggered: false,
            worker_loop_started: false,
            queue_runner_started: false,
            hermes_live_called: false,
            mcp_run_called: false,
            token_printed: false,
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
        let report = self.report("snapshot", false);
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
            "--fixture" => cli.fixture = true,
            "--snapshot" => cli.snapshot = true,
            "--json" => cli.json = true,
            "--write-report" => cli.write_report = true,
            "--no-alt-screen" => cli.no_alt_screen = true,
            "--output-dir" => {
                let value = iter
                    .next()
                    .context("--output-dir requires a following path")?;
                cli.output_dir = PathBuf::from(value);
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
        "skybridge-operator-tui -- fixture-only read-only Ratatui console\n\
\n\
Flags:\n\
  --fixture              Use deterministic fixture state (default)\n\
  --snapshot             Render non-interactive snapshot artifacts\n\
  --json                 Print report JSON to stdout\n\
  --write-report         Write report artifacts under --output-dir\n\
  --output-dir <path>    Artifact directory (default .agent/tmp/operator-tui)\n\
  --no-alt-screen        Do not enter alternate screen in interactive mode\n"
    );
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}
