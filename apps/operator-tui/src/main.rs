mod actions;
mod app;
mod collect;
mod model;
mod render;

use std::{io, time::Duration};

use anyhow::Context;
use app::{parse_cli, App};
use crossterm::{
    event::{self, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

fn main() -> anyhow::Result<()> {
    let cli = parse_cli(std::env::args().skip(1))?;
    let mut app = App::new(cli.state_mode);

    if cli.snapshot || cli.write_report || cli.json {
        let wrote_artifacts = cli.snapshot || cli.write_report;
        let output_dir = cli.artifact_output_dir();
        if wrote_artifacts {
            app.write_snapshot_artifacts(&output_dir)?;
        }

        if cli.json {
            println!("{}", serde_json::to_string_pretty(&app.report(false))?);
        } else {
            println!("{}", app.snapshot_text());
        }
        return Ok(());
    }

    run_interactive(&mut app, cli.no_alt_screen)
}

fn run_interactive(app: &mut App, no_alt_screen: bool) -> anyhow::Result<()> {
    enable_raw_mode().context("failed to enable terminal raw mode")?;
    let mut stdout = io::stdout();
    if !no_alt_screen {
        execute!(stdout, EnterAlternateScreen).context("failed to enter alternate screen")?;
    }

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("failed to initialize terminal")?;
    let result = run_loop(app, &mut terminal);

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
) -> anyhow::Result<()> {
    loop {
        terminal.draw(|frame| render::draw(frame, app))?;

        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => break,
                    KeyCode::Char('r') => app.refresh_state(),
                    KeyCode::Char('c') => {
                        let _ = actions::handle_action(actions::Action::CopySafeSummary);
                    }
                    KeyCode::Char('g') => {
                        let _ = actions::handle_action(actions::Action::GenerateCandidateFixture);
                    }
                    KeyCode::Char('v') => {
                        let _ = actions::handle_action(actions::Action::ValidateCandidate);
                    }
                    KeyCode::Char('a') => {
                        let _ = actions::handle_action(actions::Action::AppendCandidate);
                    }
                    KeyCode::Char('p') => {
                        let _ = actions::handle_action(actions::Action::PreviewBoundedAction);
                    }
                    KeyCode::Char('s') => {
                        let _ = actions::handle_action(actions::Action::StartOneGoal);
                    }
                    KeyCode::Char('h') => {
                        let _ = actions::handle_action(actions::Action::SafePause);
                    }
                    KeyCode::Char('x') => {
                        let _ = actions::handle_action(actions::Action::AbortTerminate);
                    }
                    _ => {}
                }
            }
        }
    }

    Ok(())
}
