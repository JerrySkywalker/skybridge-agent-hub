mod actions;
mod app;
mod candidate;
mod collect;
mod interactive;
mod model;
mod render;
mod single_step;

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

    run_interactive(&mut app, cli.no_alt_screen, output_dir)
}

fn run_interactive(
    app: &mut App,
    no_alt_screen: bool,
    output_dir: std::path::PathBuf,
) -> anyhow::Result<()> {
    enable_raw_mode().context("failed to enable terminal raw mode")?;
    let mut stdout = io::stdout();
    if !no_alt_screen {
        execute!(stdout, EnterAlternateScreen).context("failed to enter alternate screen")?;
    }

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("failed to initialize terminal")?;
    let result = run_loop(app, &mut terminal, &output_dir);

    disable_raw_mode().context("failed to disable terminal raw mode")?;
    if !no_alt_screen {
        execute!(terminal.backend_mut(), LeaveAlternateScreen)
            .context("failed to leave alternate screen")?;
    }
    terminal.show_cursor().context("failed to show cursor")?;

    result
}

fn run_loop(
    app: &mut App,
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    output_dir: &std::path::Path,
) -> anyhow::Result<()> {
    loop {
        terminal.draw(|frame| render::draw(frame, app))?;

        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(key) = event::read()? {
                if interactive::handle_key(app, key.code, output_dir)?
                    == interactive::InteractiveControl::Quit
                {
                    break;
                }
            }
        }
    }

    Ok(())
}
