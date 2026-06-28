use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::{
    actions::Action,
    app::App,
    model::{timeline_steps, OperatorState},
};

pub const PANELS: [&str; 5] = [
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer",
];

pub fn draw(frame: &mut Frame<'_>, app: &App) {
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),
            Constraint::Min(10),
            Constraint::Length(7),
            Constraint::Length(12),
            Constraint::Length(5),
        ])
        .split(frame.area());

    draw_header(frame, outer[0], &app.state);
    draw_timeline(frame, outer[1], &app.state);
    draw_current_object(frame, outer[2], &app.state);
    draw_action_menu(frame, outer[3]);
    draw_safety_footer(frame, outer[4], &app.state);
}

pub fn render_snapshot_text(state: &OperatorState) -> String {
    let mut lines = Vec::new();

    lines.push("SkyBridge Operator Console - MG368A Snapshot".to_string());
    lines.push("".to_string());
    lines.push(format!("## {}", PANELS[0]));
    lines.extend(header_lines(state));
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[1]));
    for step in timeline_steps(state) {
        lines.push(format!("- [{}] {}", step.status, step.label));
    }
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[2]));
    lines.extend(current_object_lines(state));
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[3]));
    for action in Action::all() {
        let suffix = if action.enabled() {
            ""
        } else {
            " [disabled in MG368A]"
        };
        lines.push(format!("- {} {}{}", action.key(), action.label(), suffix));
        if !action.enabled() {
            lines.push(format!(
                "  reasons: {}",
                action.disabled_reasons().join(", ")
            ));
        }
    }
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[4]));
    lines.extend(safety_footer_lines(state));
    lines.push("".to_string());

    lines.join("\n")
}

pub fn render_report_markdown(app: &App, snapshot_path: &str, state_path: &str) -> String {
    let report = app.report("snapshot", false);
    let disabled = report
        .disabled_actions
        .iter()
        .map(|action| format!("{} ({})", action.action, action.disabled_reasons.join(", ")))
        .collect::<Vec<_>>()
        .join("\n- ");
    let active = report
        .active_actions
        .iter()
        .map(|action| action.action)
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        "# Operator TUI MG368A Snapshot Report\n\n- schema: {}\n- mode: {}\n- fixture_used: {}\n- interactive_started: {}\n- snapshot: {}\n- state: {}\n- panels_rendered: {}\n- active_actions: {}\n- disabled_actions:\n- {}\n- mutation_attempted: false\n- append_attempted: false\n- approval_attempted: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- token_printed: false\n",
        report.schema,
        report.mode,
        report.fixture_used,
        report.interactive_started,
        snapshot_path,
        state_path,
        report.panels_rendered.join(", "),
        active,
        disabled
    )
}

fn draw_header(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(header_lines(state).join("\n"))
        .block(panel_block(PANELS[0]))
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn draw_timeline(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let items = timeline_steps(state)
        .into_iter()
        .map(|step| {
            let color = match step.status {
                "done" => Color::Green,
                "ready" => Color::Yellow,
                "blocked" => Color::Red,
                _ => Color::Gray,
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!("[{}] ", step.status), Style::default().fg(color)),
                Span::raw(step.label),
            ]))
        })
        .collect::<Vec<_>>();
    let list = List::new(items).block(panel_block(PANELS[1]));
    frame.render_widget(list, area);
}

fn draw_current_object(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(current_object_lines(state).join("\n"))
        .block(panel_block(PANELS[2]))
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn draw_action_menu(frame: &mut Frame<'_>, area: Rect) {
    let items = Action::all()
        .into_iter()
        .map(|action| {
            let disabled = !action.enabled();
            let mut label = format!("{} {}", action.key(), action.label());
            if disabled {
                label.push_str(" [disabled in MG368A]");
            }
            let style = if disabled {
                Style::default().fg(Color::DarkGray)
            } else {
                Style::default().fg(Color::Cyan)
            };
            ListItem::new(Line::from(Span::styled(label, style)))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(panel_block(PANELS[3])), area);
}

fn draw_safety_footer(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(safety_footer_lines(state).join("\n"))
        .block(panel_block(PANELS[4]))
        .style(
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn panel_block(title: &'static str) -> Block<'static> {
    Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
}

fn header_lines(state: &OperatorState) -> Vec<String> {
    vec![
        format!(
            "repo: branch={} head={} clean={} origin_aligned={}",
            state.repo.branch,
            &state.repo.head[..12],
            state.repo.worktree_clean,
            state.repo.origin_aligned
        ),
        format!(
            "cloud: health={} version={} parity={}",
            state.cloud.health,
            &state.cloud.version[..12],
            state.cloud.parity
        ),
        format!(
            "worker: id={} local={} remote={} stale={}",
            state.worker.worker_id,
            state.worker.local_status,
            state.worker.remote_status,
            state.worker.stale
        ),
        format!(
            "campaign: {} goal={} status={}",
            state.campaign.campaign_id,
            state.campaign.current_goal_id,
            state.campaign.current_goal_status
        ),
        format!("token_printed={}", state.safety.token_printed),
    ]
}

fn current_object_lines(state: &OperatorState) -> Vec<String> {
    vec![
        "Hermes candidate summary".to_string(),
        format!("candidate_path: {}", state.hermes_candidate.candidate_path),
        format!("candidate_hash: {}", state.hermes_candidate.candidate_hash),
        format!(
            "validated: {}",
            if state.hermes_candidate.candidate_validated {
                "yes"
            } else {
                "no"
            }
        ),
        format!(
            "approved/appended: {}/{}",
            state.hermes_candidate.candidate_approved, state.hermes_candidate.candidate_appended
        ),
    ]
}

fn safety_footer_lines(state: &OperatorState) -> Vec<String> {
    vec![
        "READ ONLY | fixture mode | no mutation".to_string(),
        format!(
            "no worker loop={} | no task claim={} | token_printed={}",
            !state.safety.worker_loop_started,
            !state.safety.task_claimed,
            state.safety.token_printed
        ),
    ]
}
