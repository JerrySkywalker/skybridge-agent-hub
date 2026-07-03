mod actions;
mod app;
mod candidate;
mod collect;
mod commands;
mod interactive;
mod model;
mod render;
mod runtime;
mod single_step;
mod ui_layout;
mod view_model;

use std::{io, time::Duration};

use anyhow::Context;
use app::{parse_cli, App};
use crossterm::{
    event::{self, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

fn main() -> anyhow::Result<()> {
    let cli = parse_cli(std::env::args().skip(1))?;
    let output_dir = cli.artifact_output_dir();
    let mut app = App::new(cli.state_mode, &output_dir);
    if cli.layout_scenario.is_some() {
        let report = ui_layout::run_layout_smoke(&mut app, cli.layout_scenario, &output_dir)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.runtime_scenario.is_some() {
        let report =
            runtime::run_runtime_refactor_simulation(&mut app, cli.runtime_scenario, &output_dir)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.interactive_scenario.is_some() {
        interactive::run_simulation(&mut app, cli.interactive_scenario, &output_dir)?;
        println!(
            "{}",
            serde_json::to_string_pretty(&interactive::interactive_report(&app, &output_dir))?
        );
        return Ok(());
    }

    if cli.candidate_action != candidate::CandidateAction::None {
        app.run_candidate_action(&cli);
    }
    if cli.single_step_action != single_step::SingleStepAction::None {
        app.run_single_step_action(&cli);
    }

    if cli.snapshot
        || cli.write_report
        || cli.json
        || cli.candidate_action != candidate::CandidateAction::None
        || cli.single_step_action != single_step::SingleStepAction::None
    {
        let wrote_artifacts = cli.snapshot
            || cli.write_report
            || cli.candidate_action != candidate::CandidateAction::None
            || cli.single_step_action != single_step::SingleStepAction::None;
        if wrote_artifacts {
            app.write_snapshot_artifacts(&output_dir)?;
        }

        if cli.json {
            println!("{}", app.report_json(false)?);
        } else {
            println!("{}", app.snapshot_text());
        }
        return Ok(());
    }

    run_interactive(
        &mut app,
        cli.no_alt_screen,
        output_dir,
        cli.runtime_timeout_ms,
    )
}

fn run_interactive(
    app: &mut App,
    no_alt_screen: bool,
    output_dir: std::path::PathBuf,
    runtime_timeout_ms: u64,
) -> anyhow::Result<()> {
    enable_raw_mode().context("failed to enable terminal raw mode")?;
    let mut stdout = io::stdout();
    if !no_alt_screen {
        execute!(stdout, EnterAlternateScreen).context("failed to enter alternate screen")?;
    }

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("failed to initialize terminal")?;
    let mut command_runtime =
        runtime::OperatorRuntime::new(Duration::from_millis(runtime_timeout_ms));
    let result = run_loop(app, &mut terminal, &output_dir, &mut command_runtime);

    disable_raw_mode().context("failed to disable terminal raw mode")?;
    if !no_alt_screen {
        execute!(terminal.backend_mut(), LeaveAlternateScreen)
            .context("failed to leave alternate screen")?;
    }
    terminal.show_cursor().context("failed to show cursor")?;

    runtime::write_runtime_refactor_artifacts(
        std::path::Path::new(runtime::DEFAULT_RUNTIME_REFACTOR_OUTPUT_DIR),
        app,
        &command_runtime,
    )?;

    result
}

fn run_loop(
    app: &mut App,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    output_dir: &std::path::Path,
    command_runtime: &mut runtime::OperatorRuntime,
) -> anyhow::Result<()> {
    loop {
        let events = command_runtime.poll();
        let results = runtime::apply_runtime_events(app, events);
        for result in results {
            interactive::record_command_result(app, &result, output_dir)?;
        }
        app.sync_view_model();
        terminal.draw(|frame| render::draw(frame, app))?;

        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(key) = event::read()? {
                if interactive::handle_key(app, key.code, output_dir, command_runtime)?
                    == interactive::InteractiveControl::Quit
                {
                    break;
                }
            }
        }
    }

    Ok(())
}
