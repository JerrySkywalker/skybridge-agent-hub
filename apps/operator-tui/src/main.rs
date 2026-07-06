mod actions;
mod app;
mod candidate;
mod collect;
mod commands;
mod input_ux;
mod interactive;
mod manual_reliability;
mod model;
mod render;
mod runtime;
mod single_step;
mod ui_layout;
mod ux_yolo;
mod view_model;

use std::{io, time::Duration};

use anyhow::Context;
use app::{parse_cli, App};
use crossterm::{
    event::{self, DisableBracketedPaste, EnableBracketedPaste, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

fn main() -> anyhow::Result<()> {
    let cli = parse_cli(std::env::args().skip(1))?;
    let output_dir = cli.artifact_output_dir();
    let mut app = App::new(cli.state_mode, &output_dir);
    app.language = cli.language;
    app.operator_guide = cli.operator_guide;
    app.yolo_fixture_only = cli.yolo_fixture_only;
    app.sync_view_model();
    if cli.self_drive_dry_run && !cli.yolo_fixture_only {
        anyhow::bail!("--self-drive-dry-run requires --yolo-fixture-only");
    }
    if cli.simulate_docs_pr && !cli.yolo_fixture_only {
        anyhow::bail!("--simulate-docs-pr requires --yolo-fixture-only");
    }
    if cli.simulate_docs_pr && !cli.self_drive_dry_run {
        anyhow::bail!("--simulate-docs-pr requires --self-drive-dry-run");
    }
    if cli.simulate_docs_pr {
        let report = ux_yolo::run_mg369c_docs_pr_simulation(&mut app, &output_dir)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.ux_yolo_scenario.is_some() || cli.self_drive_dry_run {
        let scenario = if cli.self_drive_dry_run {
            ux_yolo::UxYoloScenario::SelfDrive
        } else {
            cli.ux_yolo_scenario
        };
        let report = ux_yolo::run_ux_yolo_smoke(&mut app, scenario, &output_dir)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.input_ux_scenario.is_some() {
        let report = input_ux::run_input_ux_smoke(&mut app, cli.input_ux_scenario, &output_dir)?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.manual_reliability_scenario.is_some() {
        let report = manual_reliability::run_manual_reliability_smoke(
            &mut app,
            cli.manual_reliability_scenario,
            &output_dir,
        )?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    if cli.manual_dry_run_guide {
        app.manual_dry_run_guide = true;
        app.sync_view_model();
        let report = manual_reliability::run_manual_dry_run_guide(&mut app, &output_dir)?;
        if cli.json || cli.snapshot || cli.write_report {
            println!("{}", serde_json::to_string_pretty(&report)?);
            return Ok(());
        }
    }
    if cli.operator_guide && (cli.json || cli.snapshot || cli.write_report) {
        let report = ux_yolo::run_ux_yolo_smoke(
            &mut app,
            ux_yolo::UxYoloScenario::SimplifiedGuide,
            &output_dir,
        )?;
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
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
    execute!(stdout, EnableBracketedPaste).context("failed to enable bracketed paste")?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("failed to initialize terminal")?;
    let mut command_runtime =
        runtime::OperatorRuntime::new(Duration::from_millis(runtime_timeout_ms));
    let result = run_loop(app, &mut terminal, &output_dir, &mut command_runtime);

    disable_raw_mode().context("failed to disable terminal raw mode")?;
    execute!(terminal.backend_mut(), DisableBracketedPaste)
        .context("failed to disable bracketed paste")?;
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
        app.view_model.sync_running_guard(
            command_runtime.active_command_label(),
            command_runtime.active_elapsed_seconds(),
        );
        terminal.draw(|frame| render::draw(frame, app))?;

        if event::poll(Duration::from_millis(250))? {
            match event::read()? {
                Event::Key(key) => {
                    if interactive::handle_key_event(app, key, output_dir, command_runtime)?
                        == interactive::InteractiveControl::Quit
                    {
                        break;
                    }
                }
                Event::Paste(value) => {
                    interactive::handle_paste_event(app, &value, output_dir, command_runtime)?;
                }
                _ => {}
            }
        }
    }

    Ok(())
}
